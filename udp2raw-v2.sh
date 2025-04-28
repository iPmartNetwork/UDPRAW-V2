#!/bin/bash

# Color Codes
BLUE="\e[38;5;39m"
PURPLE="\e[38;5;135m"
RESET="\e[0m"

# Default Settings
DEFAULT_PORT=22490
WG_INTERFACE=wg0
UDPRAW_DIR="/opt/udpraw"
SYSTEMD_SERVICE="udpraw.service"

# Banner
clear
echo -e "${BLUE}=============================================="
echo -e "           UDPRAW WireGuard Installer"
echo -e "==============================================${RESET}"

# Get Latest Release Download URL
echo -e "${BLUE}[+] Fetching latest UDPRAW release...${RESET}"
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/iPmartnetwork/UDPRAW-V2/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo -e "${PURPLE}[!] Failed to fetch download URL. Exiting.${RESET}"
  exit 1
fi

# Download and Prepare
sudo mkdir -p $UDPRAW_DIR
cd $UDPRAW_DIR || exit

sudo curl -Lo udpr "$DOWNLOAD_URL"
sudo chmod +x udpr

echo -e "${BLUE}[+] UDPRAW downloaded and ready at ${UDPRAW_DIR}.${RESET}"

# Function to install WireGuard
install_wireguard() {
    echo -e "${BLUE}[+] Installing WireGuard...${RESET}"
    sudo apt update && sudo apt install -y wireguard
}

# Function to setup Systemd Service
create_systemd_service() {
    local port=$1

    sudo bash -c "cat > /etc/systemd/system/${SYSTEMD_SERVICE}" <<EOF
[Unit]
Description=UDPRAW Service
After=network.target

[Service]
ExecStart=${UDPRAW_DIR}/udpr -laddr 0.0.0.0:${port} -raddr 127.0.0.1:51820
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SYSTEMD_SERVICE
    sudo systemctl start $SYSTEMD_SERVICE

    echo -e "${PURPLE}[+] Systemd service created and started.${RESET}"
}

# Menu
while true; do
    echo -e "\n${BLUE}============= MENU =============${RESET}"
    echo -e "${PURPLE}1) Setup WireGuard Tunnel (Internal Server)${RESET}"
    echo -e "${PURPLE}2) Setup WireGuard Client (External Server)${RESET}"
    echo -e "${PURPLE}3) Run UDPRAW and Create Systemd Service${RESET}"
    echo -e "${PURPLE}4) Monitor WireGuard and UDPRAW${RESET}"
    echo -e "${PURPLE}5) Exit${RESET}"
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
            create_systemd_service "$port"
            ;;
        4)
            echo -e "${BLUE}--- WireGuard Status ---${RESET}"
            sudo wg show
            echo -e "${BLUE}--- UDPRAW Service Status ---${RESET}"
            sudo systemctl status $SYSTEMD_SERVICE --no-pager
            ;;
        5)
            echo -e "${BLUE}[+] Exiting.${RESET}"
            exit 0
            ;;
        *)
            echo -e "${PURPLE}[!] Invalid option. Try again.${RESET}"
            ;;
    esac
done
