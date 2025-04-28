#!/bin/bash

# =======================================
#             iPmart Network
#       UDP2RAW Multi-Server Manager
# =======================================

# --- Color Codes ---
BLUE="\e[38;5;39m"
PURPLE="\e[38;5;135m"
GREEN="\e[92m"
RED="\e[91m"
NC="\e[0m"

# --- Directories ---
EU_DIR="/etc/udp2raw/eu"
IR_DIR="/etc/udp2raw/ir"
BACKUP_DIR="/etc/udp2raw/backups"

# --- Initialization ---
mkdir -p "$EU_DIR" "$IR_DIR" "$BACKUP_DIR"

# --- Welcome Banner ---
welcome_banner() {
clear
echo -e "${BLUE}"
echo "██╗ ██████╗ ███╗   ███╗ █████╗ ██████╗ ████████╗     ██╗███╗   ██╗███████╗████████╗"
echo "██║ ██╔══██╗████╗ ████║██╔══██╗██╔══██╗╚══██╔══╝     ██║████╗  ██║██╔════╝╚══██╔══╝"
echo "██║╝██████╔╝██╔████╔██║███████║██║  ██║   ██║        ██║██╔██╗ ██║█████╗     ██║   "
echo "██║ ██╔═══╝ ██║╚██╔╝██║██╔══██║██║  ██║   ██║        ██║██║╚██╗██║██╔══╝     ██║   "
echo "██║ ██║     ██║ ╚═╝ ██║██║  ██║██████╔╝   ██║        ██║██║ ╚████║███████╗   ██║   "
echo "╚═╝╚═╝     ╚═╝     ╚═╝╚═╝  ╚═╝╚═════╝    ╚═╝        ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   "
echo -e "${NC}"
}

# --- Helper Functions ---
press_enter() { echo -e "\n${PURPLE}Press Enter to continue...${NC}"; read; }

menu_status() {
    echo -e "${BLUE}=========== Service Status ===========${NC}"
    for svc in /etc/systemd/system/udp2raw-eu-*.service; do
        [ -e "$svc" ] || continue
        name=$(basename "$svc" .service)
        if systemctl is-active --quiet "$name"; then
            echo -e "${BLUE}${name}${NC} > ${GREEN}Running${NC}"
        else
            echo -e "${BLUE}${name}${NC} > ${RED}Stopped${NC}"
        fi
    done
    for svc in /etc/systemd/system/udp2raw-ir-*.service; do
        [ -e "$svc" ] || continue
        name=$(basename "$svc" .service)
        if systemctl is-active --quiet "$name"; then
            echo -e "${PURPLE}${name}${NC} > ${GREEN}Running${NC}"
        else
            echo -e "${PURPLE}${name}${NC} > ${RED}Stopped${NC}"
        fi
    done
    echo -e "${BLUE}=======================================${NC}\n"
}

validate_port() {
    local port="$1"
    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use.${NC}"
        return 1
    fi
    return 0
}

add_server() {
    echo -e "${BLUE}Choose server type:${NC}"
    echo -e "${PURPLE}1) EU Server (Remote)${NC}"
    echo -e "${PURPLE}2) IR Server (Local)${NC}"
    read -p "Enter choice [1-2]: " server_type

    case $server_type in
        1)
            base_name="eu"
            dir="$EU_DIR"
            ;;
        2)
            base_name="ir"
            dir="$IR_DIR"
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"; return;;
    esac

    read -p "Enter unique server name: " server_name
    read -p "Local listen port [Default: 443]: " local_port
    local_port=${local_port:-443}
    validate_port "$local_port" || return

    read -p "Remote WireGuard port [Default: 40600]: " remote_port
    remote_port=${remote_port:-40600}
    read -p "Password for UDP2RAW: " password

    echo -e "${BLUE}Select protocol:${NC}"
    echo -e "${PURPLE}1) udp  2) faketcp  3) icmp${NC}"
    read -p "Protocol [1-3]: " proto_choice

    case $proto_choice in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid protocol.${NC}"; return;;
    esac

    if [[ "$base_name" == "eu" ]]; then
        listen_addr="[::]"
        target_addr="127.0.0.1"
    else
        read -p "Remote server address: " remote_address
        listen_addr="0.0.0.0"
        target_addr="$remote_address"
    fi

    cat << EOF > /etc/systemd/system/udp2raw-${base_name}-${server_name}.service
[Unit]
Description=UDP2RAW ${base_name^^} ${server_name}
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -$( [[ "$base_name" == "eu" ]] && echo 's' || echo 'c' ) -l ${listen_addr}:${local_port} -r ${target_addr}:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now udp2raw-${base_name}-${server_name}.service
    echo -e "${GREEN}Server ${server_name} added and started.${NC}"
}

remove_server() {
    echo -e "${BLUE}Select server type:${NC}"
    echo -e "${PURPLE}1) EU Server  2) IR Server${NC}"
    read -p "Choice [1-2]: " type_choice

    case $type_choice in
        1) base_name="eu";;
        2) base_name="ir";;
        *) echo -e "${RED}Invalid.${NC}"; return;;
    esac

    read -p "Enter server name to remove: " server_name
    systemctl disable --now udp2raw-${base_name}-${server_name}.service
    rm -f /etc/systemd/system/udp2raw-${base_name}-${server_name}.service
    systemctl daemon-reload
    echo -e "${GREEN}Server ${server_name} removed.${NC}"
}

backup_servers() {
    cp /etc/systemd/system/udp2raw-*.service "$BACKUP_DIR/"
    echo -e "${GREEN}Backup completed to $BACKUP_DIR.${NC}"
}

restore_servers() {
    cp "$BACKUP_DIR"/udp2raw-*.service /etc/systemd/system/
    systemctl daemon-reload
    for svc in "$BACKUP_DIR"/udp2raw-*.service; do
        name=$(basename "$svc")
        systemctl enable --now "$name"
    done
    echo -e "${GREEN}Restore completed from $BACKUP_DIR.${NC}"
}

# --- Main Loop ---

while true; do
    welcome_banner
    menu_status
    echo -e "${BLUE}Main Menu:${NC}"
    echo -e "${PURPLE}1) Add New Server"
    echo -e "${PURPLE}2) Remove Server"
    echo -e "${PURPLE}3) Backup Servers"
    echo -e "${PURPLE}4) Restore Servers"
    echo -e "${PURPLE}0) Exit${NC}"

    read -p "${GREEN}Select [0-4]: ${NC}" choice

    case $choice in
        1) add_server; press_enter;;
        2) remove_server; press_enter;;
        3) backup_servers; press_enter;;
        4) restore_servers; press_enter;;
        0) echo -e "${RED}Goodbye!${NC}"; exit 0;;
        *) echo -e "${RED}Invalid option.${NC}"; press_enter;;
    esac
done
