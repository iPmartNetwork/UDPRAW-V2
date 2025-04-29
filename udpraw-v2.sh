#!/bin/bash

# Colors
INDIGO='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
GREEN='\033[0;92m'
RED='\033[0;91m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
CONFIG_DIR="/etc/udp2raw-manager"
CONFIG_FILE="$CONFIG_DIR/servers.json"

mkdir -p "$CONFIG_DIR"
[ ! -f "$CONFIG_FILE" ] && echo "{}" > "$CONFIG_FILE"

# Helper Functions
press_enter() {
    echo -e "\n${PURPLE}Press Enter to continue...${NC}"
    read
}

save_config() {
    echo "$1" > "$CONFIG_FILE"
}

load_config() {
    cat "$CONFIG_FILE"
}

list_servers() {
    config=$(load_config)
    echo "$config" | jq -r 'keys[]?' 2>/dev/null
}

detect_architecture() {
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

install_udp2raw() {
    clear
    echo -e "${INDIGO}Installing udp2raw binaries...${NC}"
    apt-get update >/dev/null 2>&1
    apt-get install -y jq curl >/dev/null 2>&1

    arch=$(detect_architecture)

    if [ "$arch" == "unsupported" ]; then
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}"
        press_enter
        return
    fi

    latest_url=$(curl -s https://api.github.com/repos/iPmartNetwork/UDPRAW-V2/releases/latest | jq -r ".assets[] | select(.name | contains(\"$arch\")) | .browser_download_url")

    if [ -z "$latest_url" ]; then
        echo -e "${RED}Could not find a suitable binary for $arch.${NC}"
        press_enter
        return
    fi

    curl -L "$latest_url" -o /usr/local/bin/udp2raw_amd64
    chmod +x /usr/local/bin/udp2raw_amd64

    echo -e "${GREEN}udp2raw installed successfully for $arch.${NC}"
    press_enter
}

check_for_updates() {
    echo -e "${INDIGO}Checking for udp2raw updates...${NC}"
    current_version="$(/usr/local/bin/udp2raw_amd64 -h 2>&1 | grep 'udp2raw' | awk '{print $2}')"
    latest_release=$(curl -s https://api.github.com/repos/iPmartNetwork/UDPRAW-V2/releases/latest)
    latest_tag=$(echo "$latest_release" | jq -r '.tag_name')

    if [[ "$latest_tag" != "$current_version" ]]; then
        echo -e "${YELLOW}New version available: $latest_tag (Current: $current_version)${NC}"
        echo -ne "${CYAN}Do you want to update? [y/n]: ${NC}"
        read answer
        if [[ "$answer" == "y" ]]; then
            install_udp2raw
        else
            echo -e "${PURPLE}Update skipped.${NC}"
            press_enter
        fi
    else
        echo -e "${GREEN}You are using the latest version: $current_version${NC}"
        press_enter
    fi
}

add_server() {
    clear
    echo -e "${INDIGO}Adding a new server configuration${NC}"
    echo -ne "${PURPLE}Server Name: ${NC}"
    read server_name

    echo -ne "${PURPLE}Is this server located in Iran? [y/n]: ${NC}"
    read is_iran

    if [[ "$is_iran" == "y" ]]; then
        echo -ne "${PURPLE}Remote Address (IP or Domain): ${NC}"
        read remote_address
    else
        remote_address="127.0.0.1"
    fi

    echo -ne "${PURPLE}Local Listen Port (e.g., 443): ${NC}"
    read local_port

    echo -ne "${PURPLE}Remote Port: ${NC}"
    read remote_port

    echo -ne "${PURPLE}Password: ${NC}"
    read password

    echo -e "${PURPLE}Choose Protocol:${NC}"
    echo -e "  1) udp"
    echo -e "  2) faketcp"
    echo -e "  3) icmp"
    echo -ne "${CYAN}Select [1-3]: ${NC}"
    read protocol_choice

    case $protocol_choice in
        1) protocol="udp";;
        2) protocol="faketcp";;
        3) protocol="icmp";;
        *) echo -e "${RED}Invalid choice${NC}"; return;;
    esac

    config=$(load_config)
    new_entry=$(jq -n --arg lp "$local_port" --arg ra "$remote_address" --arg rp "$remote_port" --arg pw "$password" --arg pr "$protocol" \
    '{"local_port":$lp, "remote_address":$ra, "remote_port":$rp, "password":$pw, "protocol":$pr}')

    updated_config=$(echo "$config" | jq --arg name "$server_name" '. + {($name): $ARGS.named}' --argjson ARGS "$new_entry")

    save_config "$updated_config"
    create_service "$server_name"

    echo -e "${GREEN}Server added and service created!${NC}"
    press_enter
}

create_service() {
    local server_name="$1"
    local server_info=$(load_config | jq -r --arg name "$server_name" '.[$name]')
    [ -z "$server_info" ] && return

    local_port=$(echo "$server_info" | jq -r '.local_port')
    remote_address=$(echo "$server_info" | jq -r '.remote_address')
    remote_port=$(echo "$server_info" | jq -r '.remote_port')
    password=$(echo "$server_info" | jq -r '.password')
    protocol=$(echo "$server_info" | jq -r '.protocol')

    cat << EOF > "/etc/systemd/system/udp2raw-${server_name}.service"
[Unit]
Description=UDP2RAW Tunnel Service for $server_name
After=network.target

[Service]
ExecStart=/usr/local/bin/udp2raw_amd64 -c -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k "${password}" --raw-mode ${protocol} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "udp2raw-${server_name}.service"
}

remove_server() {
    clear
    echo -e "${INDIGO}Available Servers:${NC}"
    list_servers
    echo -ne "${PURPLE}Enter the server name to remove: ${NC}"
    read server_name

    config=$(load_config)
    updated_config=$(echo "$config" | jq "del(.$server_name)")
    save_config "$updated_config"

    systemctl disable --now "udp2raw-${server_name}.service" 2>/dev/null
    rm -f "/etc/systemd/system/udp2raw-${server_name}.service"
    systemctl daemon-reload

    echo -e "${GREEN}Server and service removed.${NC}"
    press_enter
}

tunnel_status() {
    clear
    echo -e "${INDIGO}Tunnel Services Status:${NC}"
    server_list=$(list_servers)
    if [ -z "$server_list" ]; then
        echo -e "${YELLOW}No servers configured yet.${NC}"
    else
        for srv in $server_list; do
            if systemctl is-active --quiet "udp2raw-${srv}.service"; then
                echo -e "${GREEN}[Running]${NC} ${PURPLE}$srv${NC}"
            else
                echo -e "${RED}[Stopped]${NC} ${PURPLE}$srv${NC}"
            fi
        done
    fi
    press_enter
}

menu() {
    while true; do
        clear
        echo -e "${INDIGO}=========== UDP2RAW Manager ===========${NC}"
        echo -e "${PURPLE}1) Install/Update udp2raw Binaries${NC}"
        echo -e "${PURPLE}2) Check for Updates${NC}"
        echo -e "${PURPLE}3) Add New Server${NC}"
        echo -e "${PURPLE}4) Remove Server${NC}"
        echo -e "${PURPLE}5) List Servers${NC}"
        echo -e "${PURPLE}6) Tunnel Services Status${NC}"
        echo -e "${PURPLE}0) Exit${NC}"
        echo -ne "${CYAN}Select an option: ${NC}"
        read choice

        case $choice in
            1) install_udp2raw;;
            2) check_for_updates;;
            3) add_server;;
            4) remove_server;;
            5) clear; list_servers; press_enter;;
            6) tunnel_status;;
            0) exit;;
            *) echo -e "${RED}Invalid option${NC}"; press_enter;;
        esac
    done
}

menu
