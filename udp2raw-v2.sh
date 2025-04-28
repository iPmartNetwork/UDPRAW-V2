#!/bin/bash

# Colors
NC='\033[0m'
PURPLE='\033[0;35m'
BLUE='\033[1;34m'
RED='\033[0;31m'

# Paths
UDP2RAW_DIR="/opt/udp2raw"
UDP2RAW_BIN="$UDP2RAW_DIR/udp2raw_amd64"
WG_DIR="/etc/wireguard"
UDP2RAW_CONF_DIR="/etc/udp2raw"
LOG_FILE="/var/log/udp2raw_wg_pro.log"

# Check requirements
check_requirements() {
    echo -e "${BLUE}Checking requirements...${NC}"
    apt update -y && apt install -y wireguard-tools dialog curl tar jq iptables-persistent || \
    yum install -y epel-release && yum install -y wireguard-tools dialog curl tar jq iptables-services || \
    { echo "Package installation failed."; exit 1; }

    if [ ! -f "$UDP2RAW_BIN" ]; then
        install_udp2raw
    fi

    mkdir -p "$WG_DIR" "$UDP2RAW_CONF_DIR/clients"
}

# Install udp2raw
install_udp2raw() {
    echo -e "${BLUE}Installing udp2raw from wangyu- official release (dynamic)...${NC}"
    mkdir -p "$UDP2RAW_DIR"
    cd "$UDP2RAW_DIR" || exit

    echo -e "${BLUE}Fetching latest udp2raw release info...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/iPmartnetwork/udp2raw/releases/latest | jq -r .tag_name)

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Failed to fetch latest udp2raw version.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Latest version found: $LATEST_VERSION${NC}"

    DOWNLOAD_URL="https://github.com/iPmartnetwork/udp2raw/releases/download/${LATEST_VERSION}/udp2raw_binaries.tar.gz"

    curl -LO "$DOWNLOAD_URL"
    if [ ! -f "udp2raw_binaries.tar.gz" ]; then
        echo -e "${RED}Failed to download udp2raw binaries.${NC}"
        exit 1
    fi

    tar -xzf udp2raw_binaries.tar.gz

    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        BIN_NAME="udp2raw_amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        BIN_NAME="udp2raw_aarch64"
    else
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi

    if [ ! -f "$BIN_NAME" ]; then
        echo -e "${RED}Binary for architecture $ARCH not found.${NC}"
        exit 1
    fi

    cp "$BIN_NAME" "$UDP2RAW_BIN"
    chmod +x "$UDP2RAW_BIN"

    echo -e "${BLUE}udp2raw installed successfully from version $LATEST_VERSION.${NC}"
}

# Generate WireGuard keys
generate_keys() {
    umask 077
    wg genkey | tee "$WG_DIR/privatekey" | wg pubkey > "$WG_DIR/publickey"
}

# Firewall Rules
setup_firewall() {
    PORT=$(dialog --inputbox "Enter the port to open (udp2raw or WireGuard port):" 8 40 4096 --stdout)
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    systemctl restart netfilter-persistent || systemctl restart iptables
    echo -e "${PURPLE}Firewall rule added for port ${PORT}.${NC}"
}

# Create WireGuard server
create_server() {
    generate_keys

    SERVER_PORT=$(dialog --inputbox "Enter WireGuard listening port:" 8 40 51820 --stdout)
    UDP2RAW_PORT=$(dialog --inputbox "Enter udp2raw listening port:" 8 40 4096 --stdout)
    PASSWORD=$(dialog --inputbox "Enter a password for udp2raw (optional):" 8 40 --stdout)
    RAW_MODE=$(dialog --menu "Select raw-mode for udp2raw:" 12 50 4 faketcp "Fake TCP" udp "UDP" icmp "ICMP" --stdout)

    PRIVATE_KEY=$(cat "$WG_DIR/privatekey")

    cat > "$WG_DIR/wg0.conf" <<EOF
[Interface]
Address = 10.0.0.1/24
PrivateKey = $PRIVATE_KEY
ListenPort = $SERVER_PORT
EOF

    pass_flag=""
    if [ -n "$PASSWORD" ]; then
        pass_flag="-k $PASSWORD"
    fi

    cat > /etc/systemd/system/udp2raw-server.service <<EOF
[Unit]
Description=udp2raw Server Tunnel
After=network.target

[Service]
ExecStart=$UDP2RAW_BIN -s -l0.0.0.0:$UDP2RAW_PORT -r 127.0.0.1:$SERVER_PORT --raw-mode $RAW_MODE $pass_flag
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable udp2raw-server
    systemctl start udp2raw-server
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    echo -e "${PURPLE}Server created and running!${NC}"
}

# Create client
create_client() {
    CLIENT_NAME=$(dialog --inputbox "Enter a name for this client:" 8 40 client1 --stdout)
    SERVER_IP=$(dialog --inputbox "Enter Server IP address:" 8 40 --stdout)
    SERVER_PORT=$(dialog --inputbox "Enter Server WireGuard port:" 8 40 51820 --stdout)
    UDP2RAW_PORT=$(dialog --inputbox "Enter udp2raw server port:" 8 40 4096 --stdout)
    PASSWORD=$(dialog --inputbox "Enter udp2raw password (leave blank if none):" 8 40 --stdout)
    RAW_MODE=$(dialog --menu "Select raw-mode for udp2raw:" 12 50 4 faketcp "Fake TCP" udp "UDP" icmp "ICMP" --stdout)
    SERVER_PUBKEY=$(dialog --inputbox "Enter WireGuard server public key:" 8 40 --stdout)

    mkdir -p "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME"
    umask 077
    wg genkey | tee "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME/privatekey" | wg pubkey > "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME/publickey"

    PRIVATE_KEY=$(cat "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME/privatekey")

    cat > "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME/wg0.conf" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.0.0.${RANDOM:0:1}/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = 127.0.0.1:$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    pass_flag=""
    if [ -n "$PASSWORD" ]; then
        pass_flag="-k $PASSWORD"
    fi

    cat > /etc/systemd/system/udp2raw-client-$CLIENT_NAME.service <<EOF
[Unit]
Description=udp2raw Client Tunnel ($CLIENT_NAME)
After=network.target

[Service]
ExecStart=$UDP2RAW_BIN -c -r$SERVER_IP:$UDP2RAW_PORT -l127.0.0.1:$SERVER_PORT --raw-mode $RAW_MODE $pass_flag
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable udp2raw-client-$CLIENT_NAME
    systemctl start udp2raw-client-$CLIENT_NAME

    cp "$UDP2RAW_CONF_DIR/clients/$CLIENT_NAME/wg0.conf" "$WG_DIR/wg0.conf"
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    echo -e "${PURPLE}Client $CLIENT_NAME created and running!${NC}"
}

# View Logs
view_logs() {
    dialog --title "udp2raw + WireGuard Logs" --textbox "$LOG_FILE" 22 70
}

# Main menu
main_menu() {
    while true; do
        CHOICE=$(dialog --backtitle "udp2raw + WireGuard Pro Setup" --title "Main Menu" --menu "Choose an option:" 15 50 6 \
        1 "Create Server" \
        2 "Create Client" \
        3 "Firewall Settings" \
        4 "View Logs" \
        5 "Exit" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1)
                create_server
                ;;
            2)
                create_client
                ;;
            3)
                setup_firewall
                ;;
            4)
                view_logs
                ;;
            5)
                exit 0
                ;;
        esac
    done
}

# Startup
check_requirements
main_menu
