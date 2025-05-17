#!/bin/bash

GREEN="\e[92m"
YELLOW="\e[93m"
CYAN="\e[96m"
RED="\e[91m"
RESET="\e[0m"

INSTALL_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

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

get_latest_version() {
    curl -s "https://api.github.com/repos/wangyu-/udp2raw/releases/latest" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/'
}

download_udp2raw() {
    local VERSION=$(get_latest_version)
    if [[ -z "$VERSION" ]]; then
        echo -e "${RED}Failed to get latest version from GitHub!${RESET}"
        exit 1
    fi
    local DL_URL="https://github.com/wangyu-/udp2raw/releases/download/${VERSION}/${BIN_NAME}"

    if [[ ! -f "$UDP2RAW_BIN" ]]; then
        echo -e "${YELLOW}Downloading udp2raw binary for $ARCH ...${RESET}"
        wget -O "$UDP2RAW_BIN" "$DL_URL"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Failed to download udp2raw from $DL_URL${RESET}"
            rm -f "$UDP2RAW_BIN"
            exit 1
        fi
        chmod +x "$UDP2RAW_BIN"
        echo -e "${GREEN}udp2raw binary downloaded successfully.${RESET}"
    else
        echo -e "${GREEN}udp2raw binary already exists.${RESET}"
    fi
}

create_udp2raw_service() {
    local port="$1"
    local backend_port="$2"
    local mode="$3"
    local password="$4"
    local service_name="udp2raw_${port}"

    local cmd="$UDP2RAW_BIN -s -l0.0.0.0:$port -r 127.0.0.1:$backend_port -k \"$password\" --raw-mode $mode -a"

    cat > "$SYSTEMD_DIR/${service_name}.service" <<EOF
[Unit]
Description=udp2raw SERVER tunnel on port $port [$mode]
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
    echo -e "${GREEN}Server service $service_name started.${RESET}"
}

create_udp2raw_client_service() {
    local local_port="$1"
    local server_ip="$2"
    local server_port="$3"
    local mode="$4"
    local password="$5"
    local service_name="udp2rawc_${local_port}"

    local cmd="$UDP2RAW_BIN -c -l0.0.0.0:$local_port -r $server_ip:$server_port -k \"$password\" --raw-mode $mode -a"

    cat > "$SYSTEMD_DIR/${service_name}.service" <<EOF
[Unit]
Description=udp2raw CLIENT tunnel [$mode] to $server_ip:$server_port
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
    echo -e "${GREEN}Client service $service_name started.${RESET}"
}

list_udp2raw_services() {
    echo -e "${YELLOW}Active udp2raw tunnels:${RESET}"
    systemctl list-units --type=service | grep udp2raw | awk '{print $1}'
}

remove_udp2raw_service() {
    local name="$1"
    systemctl stop "$name"
    systemctl disable "$name"
    rm -f "$SYSTEMD_DIR/${name}.service"
    systemctl daemon-reload
    echo -e "${GREEN}Service $name removed.${RESET}"
}

while true; do
    clear
    echo -e "${CYAN}========= UDP2RAW Tunnel Manager =========${RESET}"
    echo -e "${YELLOW}1) Download/Update udp2raw kernel"
    echo "2) Create new udp2raw SERVER tunnel"
    echo "3) Create new udp2raw CLIENT tunnel"
    echo "4) List running udp2raw tunnels"
    echo "5) Stop and remove udp2raw tunnel"
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
            download_udp2raw
            echo -ne "${CYAN}Enter LOCAL listen port (e.g. 51820): ${RESET}"
            read local_port
            echo -ne "${CYAN}Enter REMOTE SERVER IP (e.g. 1.2.3.4): ${RESET}"
            read server_ip
            echo -ne "${CYAN}Enter REMOTE SERVER PORT (e.g. 443): ${RESET}"
            read server_port
            echo -ne "${CYAN}Choose tunnel mode [udp/icmp/faketcp] (default: udp): ${RESET}"
            read mode
            mode=${mode:-udp}
            echo -ne "${CYAN}Enter tunnel password: ${RESET}"
            read password
            create_udp2raw_client_service "$local_port" "$server_ip" "$server_port" "$mode" "$password"
            read -p "Press enter to continue..."
            ;;
        4)
            list_udp2raw_services
            read -p "Press enter to continue..."
            ;;
        5)
            echo -ne "${CYAN}Enter service name (e.g. udp2raw_443 or udp2rawc_51820): ${RESET}"
            read name
            remove_udp2raw_service "$name"
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
