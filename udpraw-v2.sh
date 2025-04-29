#!/bin/bash

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

mkdir -p "$EU_DIR" "$IR_DIR" "$BACKUP_DIR"

# --- Helper Functions ---
press_enter() {
    echo -e "\\n${PURPLE}Press Enter to continue...${NC}"
    read
}

menu_status() {
    echo -e "${BLUE}=========== Service Status ===========${NC}"
    for svc in /etc/systemd/system/udp2raw-eu-*.service; do
        [ -e "$svc" ] || continue
        name=$(basename "$svc" .service)
        systemctl is-active --quiet "$name" && \
            echo -e "${BLUE}${name}${NC} > ${GREEN}Running${NC}" || \
            echo -e "${BLUE}${name}${NC} > ${RED}Stopped${NC}"
    done
    for svc in /etc/systemd/system/udp2raw-ir-*.service; do
        [ -e "$svc" ] || continue
        name=$(basename "$svc" .service)
        systemctl is-active --quiet "$name" && \
            echo -e "${PURPLE}${name}${NC} > ${GREEN}Running${NC}" || \
            echo -e "${PURPLE}${name}${NC} > ${RED}Stopped${NC}"
    done
    echo -e "${BLUE}=======================================${NC}\\n"
}

validate_port() {
    local port="$1"
    ss -tuln | grep -q ":$port " && return 1 || return 0
}
install_udp2raw_from_github() {
    clear
    echo -e "${BLUE}Installing udp2raw from GitHub releases...${NC}"
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || exit 1

    LATEST=$(curl -s https://api.github.com/repos/iPmartNetwork/UDPRAW-V2/releases/latest | grep browser_download_url | grep tar.gz | cut -d '"' -f 4)
    if [ -z "$LATEST" ]; then
        echo -e "${RED}Failed to fetch latest udp2raw release.${NC}"
        press_enter
        return
    fi

    echo -e "${BLUE}Downloading: $LATEST${NC}"
    curl -LO "$LATEST" || { echo -e "${RED}Download failed.${NC}"; press_enter; return; }

    tar -xzf *.tar.gz || { echo -e "${RED}Extraction failed.${NC}"; press_enter; return; }

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) BIN=udp2raw_amd64 ;;
        aarch64) BIN=udp2raw_aarch64 ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; press_enter; return ;;
    esac

    if [ ! -f "$BIN" ]; then
        echo -e "${RED}Binary $BIN not found after extraction.${NC}"
        press_enter
        return
    fi

    mv "$BIN" /usr/local/bin/udp2raw && chmod +x /usr/local/bin/udp2raw
    echo -e "${GREEN}udp2raw installed successfully at /usr/local/bin/udp2raw${NC}"
    press_enter
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
        1) target_dir="$EU_DIR"; prefix="udp2raw-eu" ;;
        2) target_dir="$IR_DIR"; prefix="udp2raw-ir" ;;
        *) echo -e "${RED}Invalid choice.${NC}"; press_enter; return ;;
    esac

    echo -ne "${BLUE}Enter a unique name (no spaces): ${NC}"
    read server_name
    server_name=$(echo "$server_name" | tr -d '[:space:]')
    full_service_name="${prefix}-${server_name}"

    echo -ne "${BLUE}Enter Local Bind Port: ${NC}"
    read local_port
    if ! validate_port "$local_port"; then
        echo -e "${RED}Port is already in use.${NC}"
        press_enter
        return
    fi

    echo -ne "${BLUE}Enter Remote Address (IP/Domain): ${NC}"
    read remote_address
    echo -ne "${BLUE}Enter Remote Port: ${NC}"
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
Description=udp2raw Service - ${server_name}
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
    shopt -s nullglob
    files=(/etc/systemd/system/udp2raw-*.service)
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}No servers found to backup.${NC}"
    else
        cp "${files[@]}" "$BACKUP_DIR/"
        echo -e "${GREEN}Backup completed at ${BACKUP_DIR}.${NC}"
    fi
    shopt -u nullglob
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
main_menu() {
    while true; do
        clear
        menu_status
        echo -e "${BLUE}============== Main Menu ==============${NC}"
        echo -e "${PURPLE}1) Install udp2raw from GitHub${NC}"
        echo -e "${PURPLE}2) Add New UDP2RAW Server${NC}"
        echo -e "${PURPLE}3) Remove UDP2RAW Server${NC}"
        echo -e "${PURPLE}4) Backup Servers${NC}"
        echo -e "${PURPLE}5) Restore Servers${NC}"
        echo -e "${PURPLE}0) Exit${NC}"
        echo -e "${BLUE}=======================================${NC}"
        echo ""
        echo -ne "${BLUE}Select an option [0-5]: ${NC}"
        read choice

        case "$choice" in
            1) install_udp2raw_from_github ;;
            2) add_server ;;
            3) remove_server ;;
            4) backup_servers ;;
            5) restore_servers ;;
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
