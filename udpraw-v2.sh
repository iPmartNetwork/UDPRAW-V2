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
    echo -ne "${RED}] ${progress}%${NC}"
    echo
}

if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo -e "${YELLOW}Checking packages and preparing system...${NC}\n"
    sleep 1
    for i in {4..1}; do
        echo -ne "Continuing in $i seconds\033[0K\r"
        sleep 1
    done
    echo ""
    apt-get update > /dev/null 2>&1
    display_fancy_progress 20

    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        echo -e "${RED}Unsupported architecture: $arch${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Downloading and installing udp2raw...${NC}"
    curl -L -o /usr/local/bin/udp2raw https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64
    chmod +x /usr/local/bin/udp2raw

    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20
    grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    command -v ufw > /dev/null && ufw reload > /dev/null 2>&1

    echo -e "${GREEN}Installation and configuration completed.${NC}"
}

# ... other functions (remote_func, local_func, uninstall, menu_status) should now use /usr/local/bin/udp2raw instead of /root/udp2raw_amd64
# For brevity, those functions can be updated similarly

# Main Menu Loop (unchanged, only referencing updated install function)
while true; do
    clear
    menu_status
    echo -e "\n\e[36m 1\e[0m) \e[93mInstall UDP2RAW binary"
    echo -e "\e[36m 2\e[0m) \e[93mSet EU Tunnel"
    echo -e "\e[36m 3\e[0m) \e[93mSet IR Tunnel"
    echo -e "\e[36m 4\e[0m) \e[93mUninstall UDP2RAW"
    echo -e "\e[36m 0\e[0m) \e[93mExit\n"
    echo -ne "\e[92mSelect an option \e[31m[\e[97m0-4\e[31m]: \e[0m"
    read choice

    case $choice in
        1) install ;;
        2) remote_func ;;
        3) local_func ;;
        4) uninstall ;;
        0) echo -e "\n ${RED}Exiting...${NC}"; exit 0 ;;
        *) echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}" ;;
    esac

    press_enter
done
