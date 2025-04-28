#!/bin/bash

# Color Codes
BLUE="\e[38;5;39m"
PURPLE="\e[38;5;135m"
RED="\e[38;5;196m"
NC="\e[0m"

# Default Settings
DEFAULT_PORT=22490
WG_INTERFACE=wg0
UDP2RAW_DIR="/opt/udp2raw"
UDP2RAW_BIN="/opt/udp2raw/udp2raw"
SYSTEMD_SERVICE="udp2raw"

# Banner
clear
echo -e "${BLUE}=============================================="
echo -e "           UDP2RAW WireGuard Installer"
echo -e "==============================================${NC}"

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

# Function to install WireGuard
install_wireguard() {
    echo -e "${BLUE}[+] Installing WireGuard...${NC}"
    sudo apt update && sudo apt install -y wireguard
}

# Function to setup Systemd Service for multiple servers
create_systemd_service() {
    local name=$1
    local port=$2
    local raddr=$3

    sudo bash -c "cat > /etc/systemd/system/${SYSTEMD_SERVICE}-${name}.service" <<EOF
[Unit]
Description=UDP2RAW Service for ${name}
After=network.target

[Service]
ExecStart=${UDP2RAW_BIN} -laddr 0.0.0.0:${port} -raddr ${raddr}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ${SYSTEMD_SERVICE}-${name}.service
    sudo systemctl start ${SYSTEMD_SERVICE}-${name}.service

    echo -e "${PURPLE}[+] Systemd service for ${name} created and started.${NC}"
}

# Main Install if not exists
if [ ! -f "$UDP2RAW_BIN" ]; then
    install_udp2raw
else
    echo -e "${PURPLE}[+] udp2raw already installed. Skipping installation.${NC}"
fi

# Menu
while true; do
    echo -e "\n${BLUE}============= MENU =============${NC}"
    echo -e "${PURPLE}1) Setup WireGuard Tunnel (Internal Server)${NC}"
    echo -e "${PURPLE}2) Setup WireGuard Client (External Server)${NC}"
    echo -e "${PURPLE}3) Run UDP2RAW and Create Systemd Service for Single Server${NC}"
    echo -e "${PURPLE}4) Run UDP2RAW and Create Services for Multiple Servers${NC}"
    echo -e "${PURPLE}5) Monitor WireGuard and UDP2RAW Services${NC}"
    echo -e "${PURPLE}6) Exit${NC}"
    echo -ne "${BLUE}Choose an option: ${NC}"
    read -r option

    case $option in
        1)
            install_wireguard
            sudo wg genkey | sudo tee privatekey | sudo wg pubkey > publickey
            echo -e "${PURPLE}WireGuard keys generated. Configure manually.${NC}"
            ;;
        2)
            install_wireguard
            echo -e "${PURPLE}WireGuard installed on external server. Configure manually.${NC}"
            ;;
        3)
            echo -ne "${BLUE}Enter port for UDP2RAW [default ${DEFAULT_PORT}]: ${NC}"
            read -r port
            port=${port:-$DEFAULT_PORT}
            echo -ne "${BLUE}Enter remote server address (IP:Port): ${NC}"
            read -r raddr
            create_systemd_service "single" "$port" "$raddr"
            ;;
        4)
            echo -e "${BLUE}Enter multiple servers (format: name1:IP:port,name2:IP:port):${NC}"
            read -r servers
            IFS=',' read -ra ADDR <<< "$servers"
            for entry in "${ADDR[@]}"; do
                name=$(echo "$entry" | cut -d ':' -f 1)
                ip=$(echo "$entry" | cut -d ':' -f 2)
                port=$(echo "$entry" | cut -d ':' -f 3)
                create_systemd_service "$name" "$port" "$ip:$port"
            done
            ;;
        5)
            echo -e "${BLUE}--- WireGuard Status ---${NC}"
            sudo wg show
            echo -e "${BLUE}--- UDP2RAW Services Status ---${NC}"
            sudo systemctl list-units --type=service | grep udp2raw
            ;;
        6)
            echo -e "${BLUE}[+] Exiting.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[!] Invalid option. Try again.${NC}"
            ;;
    esac
done
