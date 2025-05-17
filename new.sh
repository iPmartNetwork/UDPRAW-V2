#!/bin/bash

# =============== CONFIGURATION ===============
CYAN="\e[96m"; GREEN="\e[92m"; YELLOW="\e[93m"; RED="\e[91m"; NC="\e[0m"
UDP2RAW_URL="https://github.com/wangyu-/udp2raw/releases/download"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/udp2raw"
mkdir -p "$LOG_DIR"

# =============== FUNCTIONS ===============

# Get Public IP and Location
get_ip_info() {
    SERVER_IP=$(curl -s ifconfig.me)
    LOCATION=$(curl -s ipinfo.io/country)
    [ -z "$SERVER_IP" ] && SERVER_IP="Unavailable"
    [ -z "$LOCATION" ] && LOCATION="Unknown"
}

# Check udp2raw Installation Status
check_udp2raw_status() {
    if [ -f "$INSTALL_DIR/udp2raw" ]; then
        CORE_STATUS="${GREEN}✅ Installed${NC}"
        CORE_VER=$($INSTALL_DIR/udp2raw --version 2>/dev/null | head -n1 || echo "Unknown")
    else
        CORE_STATUS="${RED}❌ Not Installed${NC}"
        CORE_VER="N/A"
    fi
}

# Check if Any Tunnel is Active
check_tunnel_status() {
    if systemctl list-units --type=service | grep -q "udp2raw"; then
        TUNNEL_STATUS="${GREEN}✅ Running${NC}"
    else
        TUNNEL_STATUS="${RED}❌ Not Running${NC}"
    fi
}

# Install/Update udp2raw
install_udp2raw() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_NAME="amd64";;
        aarch64) ARCH_NAME="arm64";;
        armv7l) ARCH_NAME="arm";;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; return;;
    esac

    echo -e "${CYAN}Installing udp2raw for $ARCH_NAME...${NC}"
    LATEST_VER=$(curl -s https://api.github.com/repos/wangyu-/udp2raw/releases/latest | grep tag_name | cut -d '"' -f4)
    FILE_NAME="udp2raw_binaries.tar.gz"

    wget -q "${UDP2RAW_URL}/${LATEST_VER}/${FILE_NAME}" -O /tmp/$FILE_NAME
    tar -xzf /tmp/$FILE_NAME -C /tmp/
    cp /tmp/udp2raw_*$ARCH_NAME $INSTALL_DIR/udp2raw
    chmod +x $INSTALL_DIR/udp2raw
    rm -f /tmp/$FILE_NAME

    echo -e "${GREEN}udp2raw installed successfully!${NC}"
    sleep 1
}

# Create Tunnel and Service
create_tunnel() {
    read -p "Enter Foreign Server IP: " FOREIGN_IP

    # Default Tunnel Port 443, User Can Change
    read -p "Enter Local Listen Port [Default: 443]: " LOCAL_PORT
    LOCAL_PORT=${LOCAL_PORT:-443}

    # Config Port Prompt
    read -p "Enter Remote Target Port [Default: 443]: " REMOTE_PORT
    REMOTE_PORT=${REMOTE_PORT:-443}

    echo -e "${CYAN}Select Protocol:${NC} 1) UDP  2) ICMP  3) Faketcp"
    read -p "Choice [1-3]: " PROTO_CHOICE

    case $PROTO_CHOICE in
        1) PROTO="udp";;
        2) PROTO="icmp";;
        3) PROTO="faketcp";;
        *) echo -e "${RED}Invalid Protocol.${NC}"; return;;
    esac

    SERVICE_NAME="udp2raw_${LOCAL_PORT}.service"
    echo -e "${CYAN}Creating systemd service: $SERVICE_NAME${NC}"

    cat > "${SERVICE_DIR}/${SERVICE_NAME}" <<EOF
[Unit]
Description=udp2raw Tunnel on Port ${LOCAL_PORT}
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/udp2raw -s -l0.0.0.0:${LOCAL_PORT} -r${FOREIGN_IP}:${REMOTE_PORT} -k "password123" --cipher-mode xor --auth-mode simple --raw-mode ${PROTO}
Restart=always
StandardOutput=file:${LOG_DIR}/${SERVICE_NAME}.log
StandardError=file:${LOG_DIR}/${SERVICE_NAME}.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now $SERVICE_NAME
    echo -e "${GREEN}Tunnel and service created successfully!${NC}"
    sleep 1
}

# Manage Services
service_manager() {
    echo -e "${CYAN}Service Manager:${NC}"
    select opt in "List Services" "Start Service" "Stop Service" "Restart Service" "Back"; do
        case $REPLY in
            1) systemctl list-units --type=service | grep udp2raw;;
            2) read -p "Enter Service Name: " SVC; systemctl start $SVC;;
            3) read -p "Enter Service Name: " SVC; systemctl stop $SVC;;
            4) read -p "Enter Service Name: " SVC; systemctl restart $SVC;;
            5) break;;
            *) echo -e "${RED}Invalid choice!${NC}";;
        esac
    done
}

# View Logs
log_manager() {
    echo -e "${CYAN}Log Manager:${NC}"
    ls "$LOG_DIR"
    read -p "Enter log file name to view: " LOG_FILE
    tail -f "${LOG_DIR}/${LOG_FILE}"
}

# Display Status Dashboard
status_dashboard() {
    get_ip_info
    check_udp2raw_status
    check_tunnel_status

    clear
    echo -e "${YELLOW}=================== SERVER STATUS ===================${NC}"
    echo -e "Core Status  : $CORE_STATUS"
    echo -e "Core Version : ${CYAN}$CORE_VER${NC}"
    echo -e "Server IP    : ${CYAN}$SERVER_IP${NC}"
    echo -e "Location     : ${CYAN}$LOCATION${NC}"
    echo -e "Tunnel Status: $TUNNEL_STATUS"
    echo -e "${YELLOW}=====================================================${NC}\n"
}

# Main Menu
main_menu() {
    while true; do
        status_dashboard
        echo -e "${GREEN}1) Install/Update Core"
        echo -e "2) Create New Tunnel"
        echo -e "3) Service Manager"
        echo -e "4) Log Manager"
        echo -e "5) Exit${NC}"
        read -p "Select an option [1-5]: " CHOICE

        case $CHOICE in
            1) install_udp2raw;;
            2) create_tunnel;;
            3) service_manager;;
            4) log_manager;;
            5) exit 0;;
            *) echo -e "${RED}Invalid choice. Try again.${NC}"; sleep 1;;
        esac
    done
}

# Start the Script
main_menu
