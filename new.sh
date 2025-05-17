CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
NC="\e[0m"

apt update -y && apt upgrade -y

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
                echo -ne "▓"
            else
                echo -ne "░"
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

parse_ports() {
    # ورودی: رشته پورت‌ها (مثلاً: 443,444 445)
    # خروجی: آرایه پورت‌ها
    local input="$1"
    local ports=()
    # Replace commas with spaces, then split
    for port in $(echo "$input" | tr ',' ' '); do
        port=$(echo "$port" | xargs) # trim
        if [ -n "$port" ]; then
            ports+=("$port")
        fi
    done
    echo "${ports[@]}"
}

_configure_remote_params_and_create_service() {
    local config_name="$1"
    echo ""
    echo -e "\e[33mConfiguring EU Tunnel: ${GREEN}$config_name${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice for listening IP type [1-2] : ${NC}"
    read tunnel_mode_choice
    local listen_address_format
    case $tunnel_mode_choice in
        1) listen_address_format="[::]";;
        2) listen_address_format="0.0.0.0";;
        *) echo -e "${RED}Invalid choice. Aborting configuration.${NC}"; return 1;;
    esac

    local eu_listen_ports
    while true; do
        echo -ne "\e[33mEnter the port(s) for this EU server to listen on (comma or space separated, e.g., 443,8443 9443): ${NC}"
        read eu_listen_ports
        if [ -z "$eu_listen_ports" ]; then
            echo -e "${RED}Port(s) cannot be empty.${NC}"
            continue
        fi
        local valid=1
        for port in $(parse_ports "$eu_listen_ports"); do
            if ! validate_port "$port"; then valid=0; break; fi
        done
        if [ $valid -eq 1 ]; then break; fi
    done

    local wg_port
    while true; do
        echo ""
        echo -ne "\e[33mEnter the destination UDP port on this EU server (e.g., Wireguard port) \e[92m[Default: 40600]${NC}: "
        read wg_port
        if [ -z "$wg_port" ]; then wg_port=40600; fi
        if validate_port "$wg_port"; then break; fi
    done
    local password
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used on your IR server]${NC}: "
        read password
        if [ -z "$password" ]; then
            echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"
        else break; fi
    done
    local raw_mode
    echo ""
    echo -e "\e[33mProtocol (Mode) (IR and EU should be the same)${NC}"
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
        *) echo -e "${RED}Invalid choice. Aborting configuration.${NC}"; return 1;;
    esac
    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    for port in $(parse_ports "$eu_listen_ports"); do
        local exec_start_cmd="/root/udp2raw_amd64 -s -l ${listen_address_format}:${port} -r 127.0.0.1:${wg_port} -k \"${password}\" --raw-mode ${raw_mode} -a"
        _create_service_file_and_restart "${config_name}_${port}" "s" "$exec_start_cmd"
    done

    echo -e "\e[92mRemote Server (EU) configuration(s) have been set/updated and service(s) started.${NC}"
    echo -e "${GREEN}Make sure to allow UDP port(s) ${RED}$eu_listen_ports${GREEN} in your EU server's firewall (e.g., ufw allow <port>/udp).${NC}"
    echo -e "${GREEN}The service '${wg_port}' on the EU server should listen on 127.0.0.1:${wg_port}.${NC}"
    return 0
}

_configure_local_params_and_create_service() {
    local config_name="$1"
    echo ""
    echo -e "\e[33mConfiguring IR Tunnel: ${GREEN}$config_name${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC} (udp2raw listens on [::] for local app, connects to EU via IPv6 if remote_address is IPv6)"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC} (udp2raw listens on 0.0.0.0 for local app, connects to EU via IPv4 if remote_address is IPv4)"
    echo ""
    echo -ne "Enter your choice for local listening / EU connection preference [1-2] : ${NC}"
    read tunnel_mode_choice
    local local_listen_ip_format
    local remote_connect_is_ipv6=false
    case $tunnel_mode_choice in
        1) local_listen_ip_format="[::]"; remote_connect_is_ipv6=true;;
        2) local_listen_ip_format="0.0.0.0"; remote_connect_is_ipv6=false;;
        *) echo -e "${RED}Invalid choice. Aborting configuration.${NC}"; return 1;;
    esac
    local ir_listen_ports
    while true; do
        echo -ne "\e[33mEnter the port(s) for this IR server's udp2raw to listen on (comma or space separated, e.g., 40600 40601): ${NC}"
        read ir_listen_ports
        if [ -z "$ir_listen_ports" ]; then
            echo -e "${RED}Port(s) cannot be empty.${NC}"
            continue
        fi
        local valid=1
        for port in $(parse_ports "$ir_listen_ports"); do
            if ! validate_port "$port"; then valid=0; break; fi
        done
        if [ $valid -eq 1 ]; then break; fi
    done
    local eu_server_ip
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Remote server (EU) IP address (IPv${GREEN}$(if $remote_connect_is_ipv6; then echo "6"; else echo "4"; fi)${NC} address of EU server's udp2raw instance)\e[92m${NC} (This is only required on the Iranian server): "
        read eu_server_ip
        if [ -z "$eu_server_ip" ]; then echo -e "${RED}Remote server IP cannot be empty.${NC}"; else break; fi
    done
    local eu_server_listen_port
    while true; do
        echo ""
        echo -ne "\e[33mEnter the port the EU server's udp2raw is listening on \e[92m(must match EU config's listening port, e.g., 443, 8443)${NC}: "
        read eu_server_listen_port
        if [ -z "$eu_server_listen_port" ]; then echo -e "${RED}Port cannot be empty.${NC}"; continue; fi
        if validate_port "$eu_server_listen_port"; then break; fi
    done
    local password
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[Must match the password set on EU server]${NC}: "
        read password
        if [ -z "$password" ]; then echo -e "${RED}Password cannot be empty. Please enter a password.${NC}"; else break; fi
    done
    local raw_mode
    echo ""
    echo -e "\e[33mProtocol (Mode) \e[92m(Must match EU server's raw-mode)${NC}"
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
        *) echo -e "${RED}Invalid choice. Aborting configuration.${NC}"; return 1;;
    esac
    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    for port in $(parse_ports "$ir_listen_ports"); do
        local remote_server_spec
        if $remote_connect_is_ipv6 && [[ "$eu_server_ip" == *":"* ]]; then
            remote_server_spec="[${eu_server_ip}]:${eu_server_listen_port}"
        else
            remote_server_spec="${eu_server_ip}:${eu_server_listen_port}"
        fi
        local exec_start_cmd="/root/udp2raw_amd64 -c -l ${local_listen_ip_format}:${port} -r ${remote_server_spec} -k \"${password}\" --raw-mode ${raw_mode} -a"
        _create_service_file_and_restart "${config_name}_${port}" "c" "$exec_start_cmd"
    done

    echo -e "\e[92mLocal Server (IR) configuration(s) have been set/updated and service(s) started.${NC}"
    echo -e "${GREEN}Your local application (e.g. WireGuard client) should now connect to ${local_listen_ip_format}:<port> on this IR server.${NC}"
    echo -e "${GREEN}Ensure the EU server's firewall allows UDP traffic on port ${RED}$eu_server_listen_port${GREEN} from this IR server's IP.${NC}"
    return 0
}

remote_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this NEW EU (Remote) configuration (e.g., vpn1, server_A)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then break; fi
    done
    _configure_remote_params_and_create_service "$config_name"
}

local_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this NEW IR (Local) configuration (e.g., client1, home_setup)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then break; fi
    done
    _configure_local_params_and_create_service "$config_name"
}

delete_core() {
    clear
    echo -e "${YELLOW}Deleting udp2raw core binary...${NC}"
    if [ -f /root/udp2raw_amd64 ]; then
        rm -f /root/udp2raw_amd64
        echo -e "${GREEN}udp2raw core binary deleted.${NC}"
    else
        echo -e "${RED}udp2raw core binary not found.${NC}"
    fi
    press_enter
}

delete_tunnel_func() {
    clear
    echo -e "${CYAN}--- Delete a Tunnel Configuration ---${NC}"
    local services_array=()
    local counter=1
    echo -e "\n${YELLOW}Available Configurations to Delete:${NC}"
    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'; systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file"
        counter=$((counter + 1))
    done
    if [ ${#services_array[@]} -eq 0 ]; then
        echo -e "${RED}No configurations found to delete.${NC}"
        press_enter
        return
    fi
    echo -ne "\n${YELLOW}Enter the number of the configuration to delete, or 0 to return:${NC} "
    read choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services_array[@]} ]; then
        echo -e "${RED}Invalid selection.${NC}"
        press_enter
        return
    fi
    if [ "$choice" -eq 0 ]; then return; fi
    local selected_service="${services_array[$((choice - 1))]}"
    echo -e "${YELLOW}Stopping and disabling ${selected_service}...${NC}"
    systemctl stop "$selected_service" > /dev/null 2>&1
    systemctl disable "$selected_service" > /dev/null 2>&1
    rm -f "/etc/systemd/system/$selected_service"
    systemctl daemon-reload > /dev/null 2>&1
    echo -e "${GREEN}${selected_service} deleted.${NC}"
    press_enter
}

edit_tunnel_func() {
    clear
    echo -e "${CYAN}--- Edit (Reconfigure) a Tunnel Configuration ---${NC}"
    local services_array=()
    local counter=1
    echo -e "\n${YELLOW}Available Configurations to Edit:${NC}"
    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'; systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file"
        counter=$((counter + 1))
    done
    if [ ${#services_array[@]} -eq 0 ]; then
        echo -e "${RED}No configurations found to edit.${NC}"
        press_enter
        return
    fi
    echo -ne "\n${YELLOW}Enter the number of the configuration to edit, or 0 to return:${NC} "
    read choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services_array[@]} ]; then
        echo -e "${RED}Invalid selection.${NC}"
        press_enter
        return
    fi
    if [ "$choice" -eq 0 ]; then return; fi
    local selected_service="${services_array[$((choice - 1))]}"
    local base_config_name=""
    local service_type_char=""
    if [[ "$selected_service" == udp2raw-s-* ]]; then
        service_type_char="s"
        base_config_name=${selected_service#udp2raw-s-}
        base_config_name=${base_config_name%.service}
    elif [[ "$selected_service" == udp2raw-c-* ]]; then
        service_type_char="c"
        base_config_name=${selected_service#udp2raw-c-}
        base_config_name=${base_config_name%.service}
    else
        echo -e "${RED}Could not determine type for $selected_service${NC}"
        press_enter
        return
    fi
    echo -e "${YELLOW}Stopping and removing existing service...${NC}"
    systemctl stop "$selected_service" >/dev/null 2>&1
    systemctl disable "$selected_service" >/dev/null 2>&1
    rm -f "/etc/systemd/system/$selected_service"
    systemctl daemon-reload
    if [ "$service_type_char" == "s" ]; then
        _configure_remote_params_and_create_service "$base_config_name"
    elif [ "$service_type_char" == "c" ]; then
        _configure_local_params_and_create_service "$base_config_name"
    fi
    press_enter
}

get_udp2raw_version() {
    if [ -f /root/udp2raw_amd64 ]; then
        /root/udp2raw_amd64 --version 2>/dev/null | head -n1
    else
        echo "Not installed"
    fi
}

show_service_log() {
    clear
    echo -e "${CYAN}--- View UDP2RAW Service Logs ---${NC}"
    local services_array=()
    local counter=1
    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'; systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file"
        counter=$((counter + 1))
    done
    if [ ${#services_array[@]} -eq 0 ]; then
        echo -e "${RED}No UDP2RAW services found.${NC}"
        press_enter
        return
    fi
    echo -ne "\n${YELLOW}Enter the number of the service to view logs, or 0 to return:${NC} "
    read choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services_array[@]} ]; then
        echo -e "${RED}Invalid selection.${NC}"
        press_enter
        return
    fi
    if [ "$choice" -eq 0 ]; then return; fi
    local selected_service="${services_array[$((choice - 1))]}"
    echo -e "${YELLOW}Showing last 40 lines of log for ${selected_service}:${NC}\n"
    journalctl -u "$selected_service" -n 40 --no-pager
    echo -e "\n${YELLOW}For live logs: journalctl -f -u $selected_service${NC}"
    press_enter
}

menu_status() {
    local total=0
    local running=0
    local failed=0
    local stopped=0
    printf "\n${CYAN}%-40s %-12s %-30s${NC}\n" "Service Name" "Status" "Last Error/Info"
    printf "${YELLOW}%s${NC}\n" "---------------------------------------------------------------------------------------------"
    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'; systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        total=$((total+1))
        local status=$(systemctl is-active "$service_file")
        local status_color status_disp
        local last_log=""
        if [ "$status" = "active" ]; then
            status_color=$GREEN
            status_disp="Running"
            running=$((running+1))
            last_log=$(journalctl -u "$service_file" -n 1 --no-pager 2>/dev/null | tail -n1)
        elif [ "$status" = "failed" ]; then
            status_color=$RED
            status_disp="Failed"
            failed=$((failed+1))
            last_log=$(journalctl -u "$service_file" -n 1 --no-pager 2>/dev/null | tail -n1)
        else
            status_color=$YELLOW
            status_disp="Stopped"
            stopped=$((stopped+1))
            last_log="No recent log"
        fi
        printf "%-40s ${status_color}%-12s${NC} %.60s\n" "$service_file" "$status_disp" "$last_log"
    done
    printf "${YELLOW}%s${NC}\n" "---------------------------------------------------------------------------------------------"
    echo -e "${GREEN}Total:${NC} $total   ${GREEN}Running:${NC} $running   ${RED}Failed:${NC} $failed   ${YELLOW}Stopped:${NC} $stopped"
    echo -e "${CYAN}UDP2RAW Version:${NC} $(get_udp2raw_version)"
}

echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo ""
    echo -e "\e[36m 1\e[0m) \e[93mInstall/Update UDP2RAW core"
    echo -e "\e[36m 2\e[0m) \e[93mSet EU Tunnel (New)"
    echo -e "\e[36m 3\e[0m) \e[93mSet IR Tunnel (New)"
    echo -e "\e[36m 4\e[0m) \e[93mEdit a Tunnel"
    echo -e "\e[36m 5\e[0m) \e[93mDelete a Tunnel"
    echo -e "\e[36m 6\e[0m) \e[93mDelete UDP2RAW Core"
    echo -e "\e[36m 7\e[0m) \e[93mView Service Logs"
    echo -e "\e[36m 0\e[0m) \e[93mExit"
    echo ""
    echo ""
    echo -ne "\e[92mSelect an option \e[31m[\e[97m0-7\e[31m]: \e[0m"
    read choice
    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) edit_tunnel_func;;
        5) delete_tunnel_func;;
        6) delete_core;;
        7) show_service_log;;
        0) echo -e "\n ${RED}Exiting...${NC}"; exit 0;;
        *) echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}";;
    esac
    press_enter
done
