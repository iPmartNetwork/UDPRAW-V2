CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
NC="\e[0m"
BOLD="\e[1m"
UNDERLINE="\e[4m"
MAGENTA="\e[95m"
BLUE="\e[94m"
WHITE="\e[97m"
BG_BLUE="\e[44m"
BG_MAGENTA="\e[45m"
BG_CYAN="\e[46m"

apt update -y && apt upgrade -y

press_enter() {
    echo -e "\n${BOLD}${BLUE}➤${NC} ${UNDERLINE}${RED}Press Enter to continue...${NC}"
    read
}

display_fancy_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40

    while [ $progress -lt $duration ]; do
        echo -ne "\r${BG_CYAN}${WHITE}["
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "${GREEN}█${NC}"
            else
                echo -ne "${WHITE}░${NC}"
            fi
        done
        echo -ne "${WHITE}]${NC} ${BOLD}${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r${BG_CYAN}${WHITE}["
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "${GREEN}█${NC}"
    done
    echo -ne "${WHITE}]${NC} ${BOLD}${progress}%${NC}"
    echo
}

if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo ""
    echo -e "${YELLOW}First, making sure that all packages are suitable for your server.${NC}"
    echo ""
    echo -e "Please wait, it might take a while"
    echo ""
    sleep 1
    secs=4
    while [ $secs -gt 0 ]; do
        echo -ne "Continuing in $secs seconds\033[0K\r"
        sleep 1
        : $((secs--))
    done
    echo ""
    apt-get update > /dev/null 2>&1

    # Ensure jq and curl are installed
    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Installing required packages (jq, curl)...${NC}"
        apt-get install -y jq curl > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to install required packages. Please install jq and curl manually and try again.${NC}"
            return 1
        fi
    fi

    display_fancy_progress 20
    echo ""
    system_architecture=$(uname -m)

    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo -e "${RED}Unsupported architecture: $system_architecture${NC}"
        exit 1
    fi

    sleep 1
    echo ""
    echo -e "${YELLOW}Downloading and installing udp2raw (from wangyu-/udp2raw) for architecture: $system_architecture${NC}"

    LATEST_RELEASE_API_URL="https://api.github.com/repos/wangyu-/udp2raw/releases/latest"
    DOWNLOAD_URL=$(curl -s $LATEST_RELEASE_API_URL | jq -r '.assets[] | select(.name=="udp2raw_binaries.tar.gz") | .browser_download_url')

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo -e "${RED}Failed to get the download URL for udp2raw_binaries.tar.gz. Check internet or API rate limits.${NC}"
        return 1
    fi

    echo -e "${GREEN}Download URL found: $DOWNLOAD_URL${NC}"
    display_fancy_progress 10

    TMP_DIR="/tmp/udp2raw_download_$$"
    mkdir -p "$TMP_DIR"

    echo -e "${YELLOW}Downloading udp2raw_binaries.tar.gz...${NC}"
    if ! curl -L -o "$TMP_DIR/udp2raw_binaries.tar.gz" "$DOWNLOAD_URL"; then
        echo -e "${RED}Failed to download udp2raw_binaries.tar.gz.${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    display_fancy_progress 30

    echo -e "${YELLOW}Extracting archive...${NC}"
    if ! tar -xzf "$TMP_DIR/udp2raw_binaries.tar.gz" -C "$TMP_DIR"; then
        echo -e "${RED}Failed to extract udp2raw_binaries.tar.gz.${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    display_fancy_progress 10

    EXTRACTED_CONTENT_DIR=$(ls -d "$TMP_DIR"/*/ 2>/dev/null | head -n 1)
    if [ -z "$EXTRACTED_CONTENT_DIR" ]; then
        EXTRACTED_CONTENT_DIR="$TMP_DIR/"
    fi

    TARGET_BINARY_PATH_AMD64=""
    if [ -f "${EXTRACTED_CONTENT_DIR}udp2raw_amd64_hw_aes" ]; then
        TARGET_BINARY_PATH_AMD64="${EXTRACTED_CONTENT_DIR}udp2raw_amd64_hw_aes"
    elif [ -f "${EXTRACTED_CONTENT_DIR}udp2raw_amd64" ]; then
        TARGET_BINARY_PATH_AMD64="${EXTRACTED_CONTENT_DIR}udp2raw_amd64"
    else
        TARGET_BINARY_PATH_AMD64=$(find "$EXTRACTED_CONTENT_DIR" -name "udp2raw_amd64*" -type f -print -quit)
        if [ -z "$TARGET_BINARY_PATH_AMD64" ]; then
            echo -e "${RED}Could not find a suitable amd64 binary in the extracted archive.${NC}"
            echo -e "${YELLOW}Contents of $EXTRACTED_CONTENT_DIR:${NC}"
            ls -la "$EXTRACTED_CONTENT_DIR"
            rm -rf "$TMP_DIR"
            return 1
        fi
    fi

    echo -e "${GREEN}Found binary: $TARGET_BINARY_PATH_AMD64${NC}"
    cp "$TARGET_BINARY_PATH_AMD64" "/root/udp2raw_amd64"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to copy binary to /root/udp2raw_amd64.${NC}"
        rm -rf "$TMP_DIR"
        return 1
    fi

    chmod +x /root/udp2raw_amd64

    rm -rf "$TMP_DIR"
    echo -e "${GREEN}udp2raw binary installed to /root/udp2raw_amd64.${NC}"
    display_fancy_progress 10

    echo ""
    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    display_fancy_progress 20

    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi

    if ! grep -q "net.ipv6.conf.all.forwarding = 1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    fi

    sysctl -p > /dev/null 2>&1

    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw reload > /dev/null 2>&1
    fi

    echo ""
    echo -e "${GREEN}All packages were installed and configured.${NC}"
    return 0
}

validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Port must be a number.${NC}"
        return 1
    fi
    
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}Port must be between 1-65535.${NC}"
        return 1
    fi

    return 0
}

validate_config_name() {
    local name="$1"
    if [ -z "$name" ]; then
        echo -e "${RED}Configuration name cannot be empty.${NC}"
        return 1
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Configuration name can only contain alphanumeric characters, underscores, and hyphens.${NC}"
        return 1
    fi
    if [ -f "/etc/systemd/system/udp2raw-s-${name}.service" ] || [ -f "/etc/systemd/system/udp2raw-c-${name}.service" ]; then
        echo -e "${RED}A configuration with this name already exists.${NC}"
        return 1
    fi
    return 0
}

_create_service_file_and_restart() {
    local config_name="$1"
    local service_type_char="$2" # 's' or 'c'
    local exec_start_cmd="$3"
    local service_description_type=""

    if [ "$service_type_char" == "s" ]; then
        service_description_type="udp2raw-s Service"
    elif [ "$service_type_char" == "c" ]; then
        service_description_type="udp2raw-c Service"
    else
        echo -e "${RED}Invalid service type character for _create_service_file_and_restart.${NC}"
        return 1
    fi

    SERVICE_FILE_PATH="/etc/systemd/system/udp2raw-${service_type_char}-${config_name}.service"

    cat << EOF > "${SERVICE_FILE_PATH}"
[Unit]
Description=${service_description_type} (${config_name})
After=network.target

[Service]
ExecStart=${exec_start_cmd}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    if ! systemctl restart "udp2raw-${service_type_char}-${config_name}.service"; then
        echo -e "${RED}Failed to start udp2raw-${service_type_char}-${config_name} service. Check logs: journalctl -u udp2raw-${service_type_char}-${config_name}.service${NC}"
        rm -f "${SERVICE_FILE_PATH}"
        systemctl daemon-reload
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-${service_type_char}-${config_name}.service"; then
        echo -e "${RED}Failed to enable udp2raw-${service_type_char}-${config_name} service.${NC}"
        return 1
    fi
    return 0
}

remote_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this NEW EU (Remote) configuration (e.g., vpn1, server_A)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then
            break
        fi
    done

    echo ""
    echo -e "\e[33mSelect EU Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1) tunnel_mode="[::]";;
        2) tunnel_mode="0.0.0.0";;
        *) echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            return;;
    esac

    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=443
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port \e[92m[Default: 40600]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=40600
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your local server (IR)]${NC}: "
        read password
        if [ -z "$password" ]; then
            echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"
        else
            break
        fi
    done
    
    echo ""
    echo -e "\e[33mProtocol (Mode) (Local and remote should be the same)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            return;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    local exec_start_cmd="/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k \"${password}\" --raw-mode ${raw_mode} -a"

    if _create_service_file_and_restart "$config_name" "s" "$exec_start_cmd"; then
        echo -e "\e[92mRemote Server (EU) configuration '${config_name}' has been set/updated and service started.${NC}"
        echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
    fi
}

local_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this NEW IR (Local) configuration (e.g., client1, home_setup)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then
            break
        fi
    done

    echo ""
    echo -e "\e[33mSelect IR Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1) tunnel_mode="IPV6";;
        2) tunnel_mode="IPV4";;
        *) echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            return;;
    esac
    
    while true; do
        echo -ne "\e[33mEnter the Local server (IR) port \e[92m[Default: 443]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=443
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port - installed on EU \e[92m[Default: 40600]${NC}: "
        read local_port
        if [ -z "$local_port" ]; then
            local_port=40600
            break
        fi
        if validate_port "$local_port"; then
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Remote server (EU) IPV6 / IPV4 (Based on your tunnel preference)\e[92m${NC}: "
        read remote_address
        if [ -z "$remote_address" ]; then
            echo -e "${RED}Remote address cannot be empty.${NC}"
        else
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[The same as you set on remote server (EU)]${NC}: "
        read password
        if [ -z "$password" ]; then
            echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"
        else
            break
        fi
    done
    
    echo ""
    echo -e "\e[33mProtocol (Mode) \e[92m(Local and Remote should have the same value)${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}udp${NC}"
    echo -ne "${RED}2${NC}. ${YELLOW}faketcp${NC}"
    echo -e "${RED}3${NC}. ${YELLOW}icmp${NC}"
    echo ""
    echo -ne "Enter your choice [1-3] : ${NC}"
    read protocol_choice

    case $protocol_choice in
        1) raw_mode="udp";;
        2) raw_mode="faketcp";;
        3) raw_mode="icmp";;
        *) echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            return;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    local exec_start_cmd
    if [ "$tunnel_mode" == "IPV4" ]; then
        exec_start_cmd="/root/udp2raw_amd64 -c -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k \"${password}\" --raw-mode ${raw_mode} -a"
    else
        exec_start_cmd="/root/udp2raw_amd64 -c -l [::]:${local_port} -r [${remote_address}]:${remote_port} -k \"${password}\" --raw-mode ${raw_mode} -a"
    fi

    if _create_service_file_and_restart "$config_name" "c" "$exec_start_cmd"; then
        echo -e "\e[92mLocal Server (IR) configuration '${config_name}' has been set/updated and service started.${NC}"
        echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
    fi
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling ALL UDP2RAW configurations and binaries, Please wait ...${NC}"
    echo ""
    display_fancy_progress 20

    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'); do
        systemctl stop "${service_file}" > /dev/null 2>&1
        systemctl disable "${service_file}" > /dev/null 2>&1
        rm -f "/etc/systemd/system/${service_file}" > /dev/null 2>&1
    done

    for service_file in $(systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        systemctl stop "${service_file}" > /dev/null 2>&1
        systemctl disable "${service_file}" > /dev/null 2>&1
        rm -f "/etc/systemd/system/${service_file}" > /dev/null 2>&1
    done
    
    rm -f /root/udp2raw_amd64 > /dev/null 2>&1
    rm -f /root/udp2raw_x86 > /dev/null 2>&1
    
    systemctl daemon-reload > /dev/null 2>&1
    
    sleep 2
    echo ""
    echo -e "${GREEN}All UDP2RAW configurations and binaries have been uninstalled.${NC}"
}

menu_status() {
    echo ""
    echo -e "${BOLD}${UNDERLINE}${CYAN} UDP2RAW STATUS ${NC}"
    local s_services_found=0
    for service_file in $(systemctl list-units udp2raw-s-*.service --all --no-legend | awk '{print $1}'); do
        s_services_found=1
        if systemctl is-active --quiet "${service_file}"; then
            echo -e "${BG_BLUE}${WHITE} Config (${service_file}) ${NC} > ${GREEN}Running.${NC}"
        else
            local status_output=$(systemctl status "${service_file}" | grep "Active:")
            echo -e "${BG_BLUE}${WHITE} Config (${service_file}) ${NC} > ${RED}Not running. Status: ${status_output}${NC}"
        fi
    done
    if [ $s_services_found -eq 0 ]; then
        echo -e "${YELLOW}No EU Server (udp2raw-s-*) configurations found.${NC}"
    fi

    echo ""
    echo -e "${BOLD}${UNDERLINE}${MAGENTA} IR Server (Local) Configurations Status ${NC}"
    local c_services_found=0
    for service_file in $(systemctl list-units udp2raw-c-*.service --all --no-legend | awk '{print $1}'); do
        c_services_found=1
        if systemctl is-active --quiet "${service_file}"; then
            echo -ne "${BG_MAGENTA}${WHITE} Config (${service_file}) ${NC} > ${GREEN}Running.${NC}"
        else
            local status_output=$(systemctl status "${service_file}" | grep "Active:")
            echo -e "${BG_MAGENTA}${WHITE} Config (${service_file}) ${NC} > ${RED}Not running. Status: ${status_output}${NC}"
        fi
    done
    if [ $c_services_found -eq 0 ]; then
        echo -e "${YELLOW}No IR Server (udp2raw-c-*) configurations found.${NC}"
    fi
}

view_logs_func() {
    clear
    echo -e "${CYAN}--- View Configuration Logs ---${NC}"
    local services_array=()
    local counter=1

    echo -e "\n${YELLOW}Available Configurations:${NC}"
    for service_file in $(systemctl list-units udp2raw-s-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (EU Server)"
        counter=$((counter + 1))
    done
    for service_file in $(systemctl list-units udp2raw-c-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (IR Server)"
        counter=$((counter + 1))
    done

    if [ ${#services_array[@]} -eq 0 ]; then
        echo -e "\n${RED}No configurations available to view logs.${NC}"
        press_enter
        return
    fi

    echo -e "\n${YELLOW}Enter the number of the configuration to view its logs, or 0 to return to menu:${NC}"
    echo -ne "${GREEN}Select an option [0-$((${#services_array[@]}))] : ${NC}"
    read choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services_array[@]} ]; then
        echo -e "\n${RED}Invalid selection.${NC}"
        press_enter
        return
    fi

    if [ "$choice" -eq 0 ]; then
        return
    fi

    local selected_service_index=$((choice - 1))
    local service_to_log="${services_array[$selected_service_index]}"

    echo -e "\n${CYAN}Displaying last 100 log entries for ${YELLOW}${service_to_log}${CYAN}...${NC}\n"
    journalctl -u "${service_to_log}" -n 100 --no-pager
    echo -e "\n${YELLOW}For live logs, you can run: journalctl -f -u ${service_to_log}${NC}"
    press_enter
}

echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo -e "${BOLD}${UNDERLINE}${MAGENTA}========= UDP2RAW MANAGEMENT MENU =========${NC}"
    echo ""
    echo -e "${BOLD}${CYAN} 1${NC}) ${YELLOW}Install UDP2RAW binary${NC}"
    echo -e "${BOLD}${CYAN} 2${NC}) ${GREEN}Add EU Tunnel (New)${NC}"
    echo -e "${BOLD}${CYAN} 3${NC}) ${GREEN}Add IR Tunnel (New)${NC}"  
    echo -e "${BOLD}${CYAN} 4${NC}) ${BLUE}View Configuration Logs${NC}"
    echo ""
    echo -e "${BOLD}${CYAN} 5${NC}) ${RED}Uninstall ALL UDP2RAW${NC}"
    echo -e "${BOLD}${CYAN} 0${NC}) ${WHITE}Exit${NC}"
    echo ""
    echo -e "${BOLD}${UNDERLINE}${MAGENTA}==========================================${NC}"
    echo ""
    echo -ne "${BOLD}${GREEN}Select an option ${RED}[${WHITE}0-5${RED}]: ${NC}"
    read choice

    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) view_logs_func;;
        5) uninstall;;
        0) echo -e "\n ${RED}Exiting...${NC}"
            exit 0;;
        *) echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}";;
    esac

    press_enter
done
