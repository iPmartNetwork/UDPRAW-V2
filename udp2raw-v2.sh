#!/bin/bash

# Color Codes
BLUE="\e[38;5;39m"
PURPLE="\e[38;5;135m"
RESET="\e[0m"

# Default Settings
DEFAULT_PORT=22490
WG_INTERFACE=wg0
UDPRAW_DIR="/opt/udpraw"
SYSTEMD_SERVICE="udpraw"

# Banner
clear
echo -e "${BLUE}=============================================="
echo -e "           UDPRAW WireGuard Installer"
echo -e "==============================================${RESET}"

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

if [ ! -f "$UDPRAW_DIR/udpr" ]; then
    sudo curl -Lo udpr "$DOWNLOAD_URL"
    sudo chmod +x udpr
    echo -e "${BLUE}[+] UDPRAW downloaded and ready at ${UDPRAW_DIR}.${RESET}"
else
    echo -e "${PURPLE}[+] UDPRAW already installed. Skipping download.${RESET}"
fi

# Function to install WireGuard
install_wireguard() {
    echo -e "${BLUE}[+] Installing WireGuard...${RESET}"
    sudo apt update && sudo apt install -y wireguard
}

# Function to setup Systemd Service for multiple servers
create_systemd_service() {
    local name=$1
    local port=$2
    local raddr=$3

    sudo bash -c "cat > /etc/systemd/system/${SYSTEMD_SERVICE}-${name}.service" <<EOF
[Unit]
Description=UDPRAW Service for ${name}
After=network.target

[Service]
ExecStart=${UDPRAW_DIR}/udpr -laddr 0.0.0.0:${port} -raddr ${raddr}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ${SYSTEMD_SERVICE}-${name}.service
    sudo systemctl start ${SYSTEMD_SERVICE}-${name}.service

    echo -e "${PURPLE}[+] Systemd service for ${name} created and started.${RESET}"
}

# Menu
while true; do
    echo -e "\n${BLUE}============= MENU =============${RESET}"
    echo -e "${PURPLE}1) Setup WireGuard Tunnel (Internal Server)${RESET}"
    echo -e "${PURPLE}2) Setup WireGuard Client (External Server)${RESET}"
    echo -e "${PURPLE}3) Run UDPRAW and Create Systemd Service for Single Server${RESET}"
    echo -e "${PURPLE}4) Run UDPRAW and Create Services for Multiple Servers${RESET}"
    echo -e "${PURPLE}5) Monitor WireGuard and UDPRAW Services${RESET}"
    echo -e "${PURPLE}6) Exit${RESET}"
    echo -ne "${BLUE}Choose an option: ${RESET}"
    read -r option

    case $option in
        1)
            install_wireguard
            sudo wg genkey | sudo tee privatekey | sudo wg pubkey > publickey
            echo -e "${PURPLE}WireGuard keys generated. Configure manually.${RESET}"
            ;;
        2)
            install_wireguard
            echo -e "${PURPLE}WireGuard installed on external server. Configure manually.${RESET}"
            ;;
        3)
            echo -ne "${BLUE}Enter port for UDPRAW [default ${DEFAULT_PORT}]: ${RESET}"
            read -r port
            port=${port:-$DEFAULT_PORT}
            echo -ne "${BLUE}Enter remote server address (IP:Port): ${RESET}"
            read -r raddr
            create_systemd_service "single" "$port" "$raddr"
            ;;
        4)
            echo -e "${BLUE}Enter multiple servers (format: name1:IP:port,name2:IP:port):${RESET}"
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
            echo -e "${BLUE}--- WireGuard Status ---${RESET}"
            sudo wg show
            echo -e "${BLUE}--- UDPRAW Services Status ---${RESET}"
            sudo systemctl list-units --type=service | grep udpraw
            ;;
        6)
            echo -e "${BLUE}[+] Exiting.${RESET}"
            exit 0
            ;;
        *)
            echo -e "${PURPLE}[!] Invalid option. Try again.${RESET}"
            ;;
    esac
done
