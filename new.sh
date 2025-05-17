#!/bin/bash

# Colored output
GREEN="\e[92m"
YELLOW="\e[93m"
CYAN="\e[96m"
RED="\e[91m"
RESET="\e[0m"

BASE_URL="https://github.com/wangyu-/udp2raw/releases/latest/download"
INSTALL_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    BIN_NAME="udp2raw_amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    BIN_NAME="udp2raw_aarch64"
elif [[ "$ARCH" == "armv7l" ]]; then
    BIN_NAME="udp2raw_arm"
else
    echo -e "${RED}Unsupported architecture: $ARCH${RESET}"
    exit 1
fi

UDP2RAW_BIN="$INSTALL_DIR/udp2raw"

# Download function
download_udp2raw() {
    if [[ ! -f "$UDP2RAW_BIN" ]]; then
        echo -e "${YELLOW}Downloading udp2raw binary for $ARCH ...${RESET}"
        wget -O "$UDP2RAW_BIN" "$BASE_URL/$BIN_NAME" && chmod +x "$UDP2RAW_BIN"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Failed to download udp2raw!${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}udp2raw binary already exists.${RESET}"
    fi
}

# Create systemd service for each tunnel
create_udp2raw_service() {
    local port="$1"
    local backend_port="$2"
    local mode="$3"
    local password="$4"
    local service_name="udp2raw_${port}"

    # Compose udp2raw command
    local cmd="$UDP2RAW_BIN -s -l0.0.0.0:$port -r 127.0.0.1:$backend_port -k \"$password\" --raw-mode $mode -a"

    cat > "$SYSTEMD_DIR/${service_name}.service" <<EOF
[Unit]
Description=udp2raw tunnel on port $port [$mode]
After=network.target

[Service]
ExecStart=$cmd
Restart=always
User=root
LimitNOFILE=409600

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$service_name"
    echo -e "${GREEN}Service $service_name started.${RESET}"
}

# Main menu
while true; do
    clear
    echo -e "${CYAN}========= UDP2RAW Tunnel Manager =========${RESET}"
    echo -e "${YELLOW}1) Download/Update udp2raw kernel"
    echo "2) Create new udp2raw tunnel"
    echo "3) List running udp2raw tunnels"
    echo "4) Stop and remove udp2raw tunnel"
    echo "0) Exit${RESET}"
    echo -ne "${CYAN}Choose an option: ${RESET}"
    read opt

    case "$opt" in
        1)
            download_udp2raw
            read -p "Press enter to continue..."
            ;;
        2)
            download_udp2raw
            echo -ne "${CYAN}Enter tunnel port (listen, e.g. 443): ${RESET}"
            read tunnel_port
            echo -ne "${CYAN}Enter backend port (e.g. 51820 for WireGuard): ${RESET}"
            read backend_port
            echo -ne "${CYAN}Choose tunnel mode [udp/icmp/faketcp] (default: udp): ${RESET}"
            read mode
            mode=${mode:-udp}
            echo -ne "${CYAN}Enter tunnel password: ${RESET}"
            read password
            create_udp2raw_service "$tunnel_port" "$backend_port" "$mode" "$password"
            read -p "Press enter to continue..."
            ;;
        3)
            echo -e "${YELLOW}Active udp2raw tunnels:${RESET}"
            systemctl list-units --type=service | grep udp2raw_
            read -p "Press enter to continue..."
            ;;
        4)
            echo -ne "${CYAN}Enter tunnel port to remove: ${RESET}"
            read port
            service_name="udp2raw_${port}"
            systemctl stop "$service_name"
            systemctl disable "$service_name"
            rm -f "$SYSTEMD_DIR/${service_name}.service"
            systemctl daemon-reload
            echo -e "${GREEN}Service $service_name removed.${RESET}"
            read -p "Press enter to continue..."
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option!${RESET}"
            sleep 1
            ;;
    esac
done
