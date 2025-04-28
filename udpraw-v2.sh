#!/bin/bash

# ==============================================
#          UDP2RAW Multi-Server Manager
# ==============================================

# --- Colors ---
BLUE="\e[38;5;39m"
PURPLE="\e[38;5;135m"
GREEN="\e[92m"
RED="\e[91m"
NC="\e[0m"

# --- Directories ---
EU_DIR="/etc/udp2raw/eu"
IR_DIR="/etc/udp2raw/ir"
BACKUP_DIR="/etc/udp2raw/backups"

# --- Initialize directories ---
mkdir -p "$EU_DIR" "$IR_DIR" "$BACKUP_DIR"

# --- Helper functions ---
press_enter() {
    echo -e "\\n${PURPLE}Press Enter to continue...${NC}"
    read
}

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
    echo -e "${BLUE}=======================================${NC}\\n"
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
    clear
    echo -e "${BLUE}Add New UDP2RAW Server${NC}"
    echo ""
    echo -e "${PURPLE}1) EU Server (Outside Tunnel)${NC}"
    echo -e "${PURPLE}2) IR Server (Inside Tunnel)${NC}"
    echo ""
    echo -ne "${BLUE}Choose server type [1-2]: ${NC}"
    read server_type

    case $server_type in
        1)
            target_dir="$EU_DIR"
            prefix="udp2raw-eu"
            ;;
        2)
            target_dir="$IR_DIR"
            prefix="udp2raw-ir"
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            press_enter
            return
            ;;
    esac

    echo -ne "${BLUE}Enter a unique name for this server (no spaces): ${NC}"
    read server_name
    full_service_name="${prefix}-${server_name}"

    echo -ne "${BLUE}Enter Local Bind Port: ${NC}"
    read local_port
    if ! validate_port "$local_port"; then
        press_enter
        return
    fi

    echo -ne "${BLUE}Enter Remote Target IP or Domain: ${NC}"
    read remote_address

    echo -ne "${BLUE}Enter Remote Target Port: ${NC}"
    read remote_port

    echo -ne "${BLUE}Enter Password (Key): ${NC}"
    read password

    echo -e "${PURPLE}Choose Raw Mode:${NC}"
    echo -e "${PURPLE}1) faketcp${NC}"
    echo -e "${PURPLE}2) udp${NC}"
    echo -e "${PURPLE}3) icmp${NC}"
    echo -ne "${BLUE}Select mode [1-3]: ${NC}"
    read mode_choice

    case $mode_choice in
        1) raw_mode="faketcp" ;;
        2) raw_mode="udp" ;;
        3) raw_mode="icmp" ;;
        *) echo -e "${RED}Invalid mode.${NC}"; press_enter; return ;;
    esac

    # Create systemd service
    cat <<EOF > /etc/systemd/system/${full_service_name}.service
[Unit]
Description=udp2raw Service for ${server_name}
After=network.target

[Service]
ExecStart=/usr/local/bin/udp2raw -s -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${full_service_name}
    systemctl start ${full_service_name}

    echo -e "${GREEN}Server ${full_service_name} added and started successfully!${NC}"
    press_enter
}
remove_server() {
    clear
    echo -e "${BLUE}Remove UDP2RAW Server${NC}"
    echo ""
    echo -ne "${BLUE}Enter Service Name to Remove (e.g., udp2raw-eu-myserver): ${NC}"
    read service_name

    systemctl stop "${service_name}"
    systemctl disable "${service_name}"
    rm -f "/etc/systemd/system/${service_name}.service"

    systemctl daemon-reload

    echo -e "${GREEN}Server ${service_name} removed successfully.${NC}"
    press_enter
}

backup_servers() {
    clear
    echo -e "${BLUE}Backup UDP2RAW Servers${NC}"
    mkdir -p "${BACKUP_DIR}"
    cp /etc/systemd/system/udp2raw-*.service "${BACKUP_DIR}/"
    echo -e "${GREEN}Backup completed at ${BACKUP_DIR}.${NC}"
    press_enter
}

restore_servers() {
    clear
    echo -e "${BLUE}Restore UDP2RAW Servers${NC}"
    if ls ${BACKUP_DIR}/udp2raw-*.service 1> /dev/null 2>&1; then
        cp ${BACKUP_DIR}/udp2raw-*.service /etc/systemd/system/
        systemctl daemon-reload
        echo -e "${GREEN}Restore completed.${NC}"
    else
        echo -e "${RED}No backup files found.${NC}"
    fi
    press_enter
}

manual_install() {
    clear
    echo -e "${BLUE}Manual Install of udp2raw${NC}"
    echo ""
    echo -ne "${BLUE}Enter the local file path or direct URL to udp2raw binary: ${NC}"
    read file_path

    if [[ "$file_path" == http* ]]; then
        curl -Lo /usr/local/bin/udp2raw "$file_path"
    else
        cp "$file_path" /usr/local/bin/udp2raw
    fi

    chmod +x /usr/local/bin/udp2raw
    echo -e "${GREEN}udp2raw installed manually at /usr/local/bin/udp2raw${NC}"
    press_enter
}
main_menu() {
    while true; do
        clear
        menu_status
        echo -e "${BLUE}============== Main Menu ==============${NC}"
        echo -e "${PURPLE}1) Add New UDP2RAW Server${NC}"
        echo -e "${PURPLE}2) Remove UDP2RAW Server${NC}"
        echo -e "${PURPLE}3) Backup Servers${NC}"
        echo -e "${PURPLE}4) Restore Servers${NC}"
        echo -e "${PURPLE}5) Manual Install udp2raw${NC}"
        echo -e "${PURPLE}0) Exit${NC}"
        echo -e "${BLUE}=======================================${NC}"
        echo ""
        echo -ne "${BLUE}Select an option [0-5]: ${NC}"
        read choice

        case "$choice" in
            1) add_server ;;
            2) remove_server ;;
            3) backup_servers ;;
            4) restore_servers ;;
            5) manual_install ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice.${NC}"; press_enter ;;
        esac
    done
}
# --- Start the program ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root.${NC}"
    exit 1
fi

main_menu
