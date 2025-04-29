#!/bin/bash

CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
NC="\e[0m"

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
    local used=$(ss -tuln | grep -w ":$port" | wc -l)
    if [[ $used -gt 0 ]]; then
        echo -e "${RED}Port $port is already in use. Choose another.${NC}"
        return 1
    fi
    return 0
}

remote_func() {
    clear
    echo -e "${CYAN}Configure EU Tunnel (Server)${NC}\n"

    echo -e "${YELLOW}Choose IP mode:${NC}"
    echo -e "${GREEN}1)${NC} IPv6"
    echo -e "${GREEN}2)${NC} IPv4"
    read -rp "Enter your choice [1-2]: " mode

    tunnel_ip="[::]"
    [[ "$mode" == "2" ]] && tunnel_ip="0.0.0.0"

    read -rp "Local listening port [default 443]: " local_port
    local_port=${local_port:-443}
    while ! validate_port "$local_port"; do
        read -rp "Enter a different port: " local_port
    done

    read -rp "WireGuard backend port [default 40600]: " remote_port
    remote_port=${remote_port:-40600}
    while ! validate_port "$remote_port"; do
        read -rp "Enter a different port: " remote_port
    done

    read -srp "Password for UDP2RAW: " password
    echo ""

    echo -e "${YELLOW}Choose protocol:${NC}"
    echo -e "${GREEN}1)${NC} UDP"
    echo -e "${GREEN}2)${NC} FakeTCP"
    echo -e "${GREEN}3)${NC} ICMP"
    read -rp "Select mode [1-3]: " proto

    case $proto in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid protocol.${NC}"; return;;
    esac

    cat << EOF > /etc/systemd/system/udp2raw-s.service
[Unit]
Description=UDP2RAW EU Server Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/udp2raw -s -l ${tunnel_ip}:${local_port} -r 127.0.0.1:${remote_port} -k "$password" --raw-mode $raw_mode -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now udp2raw-s.service
    echo -e "${GREEN}EU Tunnel service started successfully.${NC}"
    echo -e "${YELLOW}Run: ${RED}ufw allow $remote_port${NC} ${YELLOW}to open the port if using UFW.${NC}"
}

local_func() {
    clear
    echo -e "${CYAN}Configure IR Tunnel (Client)${NC}\n"

    echo -e "${YELLOW}Choose IP mode:${NC}"
    echo -e "${GREEN}1)${NC} IPv6"
    echo -e "${GREEN}2)${NC} IPv4"
    read -rp "Enter your choice [1-2]: " mode

    tunnel_mode="IPv6"
    [[ "$mode" == "2" ]] && tunnel_mode="IPv4"

    read -rp "Remote port to forward (e.g. WireGuard) [default 443]: " remote_port
    remote_port=${remote_port:-443}
    while ! validate_port "$remote_port"; do
        read -rp "Enter a different port: " remote_port
    done

    read -rp "Local bind port [default 40600]: " local_port
    local_port=${local_port:-40600}
    while ! validate_port "$local_port"; do
        read -rp "Enter a different port: " local_port
    done

    read -rp "EU server IP (IPv4 or IPv6): " remote_address
    read -srp "Password for UDP2RAW: " password
    echo ""

    echo -e "${YELLOW}Choose protocol:${NC}"
    echo -e "${GREEN}1)${NC} UDP"
    echo -e "${GREEN}2)${NC} FakeTCP"
    echo -e "${GREEN}3)${NC} ICMP"
    read -rp "Select mode [1-3]: " proto

    case $proto in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid protocol.${NC}"; return;;
    esac

    [[ "$tunnel_mode" == "IPv6" ]] && bind_ip="[::]" remote_fmt="[${remote_address}]" || bind_ip="0.0.0.0" remote_fmt="${remote_address}"

    cat << EOF > /etc/systemd/system/udp2raw-c.service
[Unit]
Description=UDP2RAW IR Client Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/udp2raw -c -l ${bind_ip}:${local_port} -r ${remote_fmt}:${remote_port} -k "$password" --raw-mode $raw_mode -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now udp2raw-c.service
    echo -e "${GREEN}IR Tunnel service started successfully.${NC}"
    echo -e "${YELLOW}Run: ${RED}ufw allow $remote_port${NC} ${YELLOW}if UFW is active.${NC}"
}

uninstall() {
    clear
    echo -e "${YELLOW}Removing UDP2RAW and services...${NC}"
    display_fancy_progress 20

    systemctl disable --now udp2raw-s.service udp2raw-c.service 2>/dev/null
    rm -f /etc/systemd/system/udp2raw-{s,c}.service
    rm -f /usr/local/bin/udp2raw
    systemctl daemon-reload

    echo -e "${GREEN}UDP2RAW has been removed from the system.${NC}"
}

menu_status() {
    local s_status c_status
    systemctl is-active udp2raw-s.service &>/dev/null && s_status="${GREEN}Active${NC}" || s_status="${RED}Inactive${NC}"
    systemctl is-active udp2raw-c.service &>/dev/null && c_status="${GREEN}Active${NC}" || c_status="${RED}Inactive${NC}"

    echo -e "\n${CYAN}Service Status${NC}"
    echo -e "EU Tunnel: $s_status"
    echo -e "IR Tunnel: $c_status\n"
}

install() {
    clear
    echo -e "${YELLOW}Installing and configuring udp2raw...${NC}\n"
    apt-get update -qq
    display_fancy_progress 20

    arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        echo -e "${RED}Unsupported architecture: $arch${NC}"
        exit 1
    fi

    curl -sSL -o /usr/local/bin/udp2raw https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64
    chmod +x /usr/local/bin/udp2raw

    grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null

    if command -v ufw > /dev/null; then ufw reload > /dev/null; fi
    echo -e "${GREEN}Installation complete.${NC}"
}

# ==== MAIN MENU LOOP ====
if [ "$EUID" -ne 0 ]; then
    echo -e "\n${RED}Run this script as root.${NC}"
    exit 1
fi

while true; do
    clear
    menu_status
    echo -e "${CYAN}UDP2RAW Tunnel Manager${NC}"
    echo -e "${BLUE}1)${NC} Install UDP2RAW"
    echo -e "${BLUE}2)${NC} Configure EU Tunnel"
    echo -e "${BLUE}3)${NC} Configure IR Tunnel"
    echo -e "${BLUE}4)${NC} Uninstall UDP2RAW"
    echo -e "${BLUE}0)${NC} Exit"
    echo -ne "\n${GREEN}Choose an option [0-4]: ${NC}"
    read choice

    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) uninstall;;
        0) echo -e "${RED}Goodbye!${NC}"; exit 0;;
        *) echo -e "${RED}Invalid option.${NC}";;
    esac

    press_enter
done
