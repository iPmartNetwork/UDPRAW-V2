#!/bin/bash

CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
NC="\e[0m"

UDP2RAW_BIN="/usr/local/bin/udp2raw"
SYSTEMD_DIR="/etc/systemd/system"

press_enter() {
    echo -e "\n${RED}Press Enter to continue... ${NC}"
    read
}

display_fancy_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40

    while [ $progress -lt $duration ]; do
        echo -ne "\r[${YELLOW}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "\u2593"
            else
                echo -ne "\u2591"
            fi
        done
        echo -ne "${RED}] ${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r[${YELLOW}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "#"
    done
    echo -ne "${RED}] 100%${NC}\n"
}

validate_port() {
    local port="$1"
    if ss -tuln | grep -q ":$port"; then
        echo -e "${RED}Port $port is already in use.${NC}"
        return 1
    fi
    return 0
}

install_udp2raw() {
    clear
    echo -e "${YELLOW}Installing udp2raw...${NC}\n"
    apt-get update -qq
    display_fancy_progress 10

    arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        echo -e "${RED}Unsupported architecture: $arch${NC}"
        exit 1
    fi

    curl -sSL -o "$UDP2RAW_BIN" https://github.com/iPmartNetwork/UDPRAW-V2/releases/download/20230206.0/udp2raw_amd64
    chmod +x "$UDP2RAW_BIN"

    grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null

    if command -v ufw > /dev/null; then ufw reload > /dev/null; fi
    echo -e "${GREEN}udp2raw installed.${NC}"
}

create_tunnel() {
    clear
    echo -e "${CYAN}Create New Tunnel${NC}"

    read -rp "Tunnel Label (no spaces): " label
    if [ -z "$label" ]; then echo -e "${RED}Label cannot be empty.${NC}"; return; fi

    read -rp "Mode (server/client) [s/c]: " mode
    [[ "$mode" == "s" ]] && role="-s" || role="-c"

    read -rp "Local port (bind) [default 443]: " local_port
    local_port=${local_port:-443}
    while ! validate_port "$local_port"; do
        read -rp "Enter another local port: " local_port
    done

    read -rp "Remote IP:Port [format: ip:port]: " remote
    read -srp "Tunnel Password: " password
    echo ""

    echo -e "${YELLOW}Select Protocol:${NC}"
    echo -e "${GREEN}1)${NC} UDP"
    echo -e "${GREEN}2)${NC} FakeTCP"
    echo -e "${GREEN}3)${NC} ICMP"
    read -rp "Choose [1-3]: " proto

    case $proto in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid protocol.${NC}"; return;;
    esac

    cat << EOF > "$SYSTEMD_DIR/udp2raw-$label.service"
[Unit]
Description=UDP2RAW Tunnel $label
After=network.target

[Service]
ExecStart=$UDP2RAW_BIN $role -l 0.0.0.0:${local_port} -r ${remote} -k "$password" --raw-mode $raw_mode -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now udp2raw-$label.service
    echo -e "${GREEN}Tunnel $label created and started.${NC}"
}

list_tunnels() {
    clear
    echo -e "${CYAN}Existing Tunnels:${NC}"
    systemctl list-units --type=service --state=active,inactive | grep udp2raw- | awk '{print $1}'
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "1) Start a tunnel"
    echo -e "2) Stop a tunnel"
    echo -e "3) Remove a tunnel"
    echo -e "0) Back to main menu"

    read -rp "Choose [0-3]: " action

    case $action in
        1)
            read -rp "Tunnel Label to Start: " label
            systemctl start udp2raw-$label.service
            ;;
        2)
            read -rp "Tunnel Label to Stop: " label
            systemctl stop udp2raw-$label.service
            ;;
        3)
            read -rp "Tunnel Label to Remove: " label
            systemctl disable --now udp2raw-$label.service
            rm -f "$SYSTEMD_DIR/udp2raw-$label.service"
            systemctl daemon-reload
            echo -e "${RED}Tunnel $label deleted.${NC}"
            ;;
        0)
            return;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            ;;
    esac
}

uninstall_udp2raw() {
    clear
    echo -e "${YELLOW}Uninstalling UDP2RAW...${NC}"
    systemctl list-units --type=service | grep udp2raw- | awk '{print $1}' | while read svc; do
        systemctl disable --now "$svc"
        rm -f "$SYSTEMD_DIR/$svc"
    done
    rm -f "$UDP2RAW_BIN"
    systemctl daemon-reload
    echo -e "${GREEN}All UDP2RAW tunnels removed.${NC}"
}

# Main Menu
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root.${NC}"
    exit 1
fi

while true; do
    clear
    echo -e "${CYAN}UDP2RAW Multi-Server Manager${NC}\n"
    echo -e "${BLUE}1)${NC} Install udp2raw"
    echo -e "${BLUE}2)${NC} Create New Tunnel"
    echo -e "${BLUE}3)${NC} Manage Existing Tunnels"
    echo -e "${BLUE}4)${NC} Uninstall All"
    echo -e "${BLUE}0)${NC} Exit\n"
    read -rp "Select option [0-4]: " menu_choice

    case $menu_choice in
        1) install_udp2raw;;
        2) create_tunnel;;
        3) list_tunnels;;
        4) uninstall_udp2raw;;
        0) echo -e "${RED}Goodbye.${NC}"; exit 0;;
        *) echo -e "${RED}Invalid choice.${NC}";;
    esac

    press_enter
done
