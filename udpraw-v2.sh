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

if [ "$EUID" -ne 0 ]; then
    echo -e "\n${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo -e "${YELLOW}Initializing environment...${NC}\n"
    sleep 1
    for i in {4..1}; do
        echo -ne "Preparing in $i seconds...\033[0K\r"
        sleep 1
    done

    apt-get update -qq
    display_fancy_progress 20

    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        echo -e "${RED}Unsupported architecture detected: $arch${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Installing udp2raw binary...${NC}"
    curl -sSL -o /usr/local/bin/udp2raw https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64
    chmod +x /usr/local/bin/udp2raw

    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20

    grep -q "^net.ipv4.ip_forward = 1" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    grep -q "^net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null

    if command -v ufw > /dev/null; then
        ufw reload > /dev/null
    fi

    echo -e "${GREEN}udp2raw has been installed and configured successfully.${NC}"
}

menu_status() {
    local remote_status
    local local_status

    systemctl is-active udp2raw-s.service &> /dev/null && remote_status=0 || remote_status=1
    systemctl is-active udp2raw-c.service &> /dev/null && local_status=0 || local_status=1

    echo ""
    if [ $remote_status -eq 0 ]; then
        echo -e "${CYAN}EU Tunnel Status${NC} > ${GREEN}Running${NC}"
    else
        echo -e "${CYAN}EU Tunnel Status${NC} > ${RED}Stopped${NC}"
    fi

    if [ $local_status -eq 0 ]; then
        echo -e "${CYAN}IR Tunnel Status${NC} > ${GREEN}Running${NC}"
    else
        echo -e "${CYAN}IR Tunnel Status${NC} > ${RED}Stopped${NC}"
    fi
    echo ""
}

while true; do
    clear
    menu_status
    echo -e "${CYAN}UDP2RAW Tunnel Manager${NC}\n"
    echo -e "${BLUE}1)${NC} Install UDP2RAW"
    echo -e "${BLUE}2)${NC} Configure EU Tunnel"
    echo -e "${BLUE}3)${NC} Configure IR Tunnel"
    echo -e "${BLUE}4)${NC} Uninstall UDP2RAW"
    echo -e "${BLUE}0)${NC} Exit"
    echo -ne "\n${GREEN}Select an option${NC} [${YELLOW}0-4${NC}]: "
    read choice

    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) uninstall;;
        0) echo -e "\n${RED}Exiting...${NC}"; exit 0;;
        *) echo -e "\n${RED}Invalid selection. Try again.${NC}";;
    esac

    press_enter
done
