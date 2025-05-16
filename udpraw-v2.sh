
#!/bin/bash

CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
NC="\e[0m"

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════╗"
    echo "║         🔥 UDP2RAW INSTALLER 🔥        ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

show_loader() {
    local duration=$1
    local i=0
    sp='/-\|'
    echo -n "Processing "
    while [ $i -lt $duration ]; do
        printf "\b${sp:i%${#sp}:1}"
        sleep 0.1
        ((i++))
    done
    echo ""
}

install_udp2raw() {
    show_banner
    echo -e "${YELLOW}Checking system architecture...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) FILE="udp2raw_amd64";;
        aarch64) FILE="udp2raw_aarch64";;
        armv7l) FILE="udp2raw_arm";;
        *) 
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac

    echo -e "${YELLOW}Detecting latest version from GitHub...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/wangyu-/udp2raw/releases/latest | grep "tag_name" | cut -d '"' -f 4)
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}Failed to detect latest version. Please check your internet connection.${NC}"
        exit 1
    fi

    DOWNLOAD_URL="https://github.com/wangyu-/udp2raw/releases/download/${LATEST_VERSION}/${FILE}"

    echo -e "${GREEN}Downloading udp2raw binary for $ARCH...${NC}"
    curl -L -o /usr/local/bin/udp2raw "$DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Download failed. Please check the URL or your network.${NC}"
        exit 1
    fi

    chmod +x /usr/local/bin/udp2raw
    echo -e "${GREEN}✅ Installation completed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Run 'udp2raw -h' to check available options.${NC}"
}

manage_service() {
    echo ""
    echo -e "${YELLOW}1) Start UDP2RAW Service"
    echo -e "2) Stop UDP2RAW Service"
    echo -e "3) Service Status"
    echo -e "4) Remove UDP2RAW"
    echo -e "0) Back to Main Menu${NC}"
    read -p "Select an option [0-4]: " option

    case "$option" in
        1) systemctl start udp2raw && echo -e "${GREEN}✅ Service Started${NC}" ;;
        2) systemctl stop udp2raw && echo -e "${RED}❌ Service Stopped${NC}" ;;
        3) systemctl status udp2raw --no-pager ;;
        4) systemctl disable udp2raw && rm -f /usr/local/bin/udp2raw && echo -e "${RED}❌ UDP2RAW Removed${NC}" ;;
        0) return ;;
        *) echo -e "${RED}Invalid Option!${NC}" ;;
    esac
    read -p "Press Enter to continue..."
}

while true; do
    show_banner
    echo -e "${GREEN}1) Install udp2raw"
    echo -e "2) Manage udp2raw Service"
    echo -e "0) Exit${NC}"
    read -p "Select an option [0-2]: " main_option

    case "$main_option" in
        1) install_udp2raw ;;
        2) manage_service ;;
        0) echo -e "${RED}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option selected!${NC}" ;;
    esac
done
