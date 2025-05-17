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

    # The extracted folder is typically named 'udp2raw_binaries'
    # Or sometimes the version number like '20230301.0'
    # We need to find the binary within the extracted content.
    # Common names are udp2raw_amd64_hw_aes or udp2raw_amd64
    
    EXTRACTED_CONTENT_DIR=$(ls -d "$TMP_DIR"/*/ 2>/dev/null | head -n 1)
    if [ -z "$EXTRACTED_CONTENT_DIR" ]; then # If no subdirectory, check current tmp dir
        EXTRACTED_CONTENT_DIR="$TMP_DIR/"
    fi

    TARGET_BINARY_PATH_AMD64=""
    if [ -f "${EXTRACTED_CONTENT_DIR}udp2raw_amd64_hw_aes" ]; then
        TARGET_BINARY_PATH_AMD64="${EXTRACTED_CONTENT_DIR}udp2raw_amd64_hw_aes"
    elif [ -f "${EXTRACTED_CONTENT_DIR}udp2raw_amd64" ]; then
        TARGET_BINARY_PATH_AMD64="${EXTRACTED_CONTENT_DIR}udp2raw_amd64"
    else
        # Fallback: search for any file starting with udp2raw_amd64 in the extracted directory
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

remote_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this EU (Remote) configuration (e.g., vpn1, server_A)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then
            break
        fi
    done

    echo ""
    echo -e "\e[33mSelect EU Tunnel Mode for configuration: ${GREEN}$config_name${NC}"
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
            remote_func
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
            remote_func
            return;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    cat << EOF > /etc/systemd/system/udp2raw-s-${config_name}.service
[Unit]
Description=udp2raw-s Service (${config_name})
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    if ! systemctl restart "udp2raw-s-${config_name}.service"; then
        echo -e "${RED}Failed to start udp2raw-s-${config_name} service. Check the logs with: journalctl -u udp2raw-s-${config_name}.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-s-${config_name}.service"; then
        echo -e "${RED}Failed to enable udp2raw-s-${config_name} service.${NC}"
        return 1
    fi
    
    sleep 1

    echo -e "\e[92mRemote Server (EU) configuration '${config_name}' has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

local_func() {
    clear
    echo ""
    local config_name
    while true; do
        echo -ne "\e[33mEnter a unique name for this IR (Local) configuration (e.g., client1, home_setup)${NC}: "
        read config_name
        if validate_config_name "$config_name"; then
            break
        fi
    done

    echo ""
    echo -e "\e[33mSelect IR Tunnel Mode for configuration: ${GREEN}$config_name${NC}"
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
            local_func
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
            local_func
            return;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    if [ "$tunnel_mode" == "IPV4" ]; then
        exec_start="/root/udp2raw_amd64 -c -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    else
        exec_start="/root/udp2raw_amd64 -c -l [::]:${local_port} -r [${remote_address}]:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    fi

    cat << EOF > /etc/systemd/system/udp2raw-c-${config_name}.service
[Unit]
Description=udp2raw-c Service (${config_name})
After=network.target

[Service]
ExecStart=${exec_start}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    if ! systemctl restart "udp2raw-c-${config_name}.service"; then
        echo -e "${RED}Failed to start udp2raw-c-${config_name} service. Check the logs with: journalctl -u udp2raw-c-${config_name}.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-c-${config_name}.service"; then
        echo -e "${RED}Failed to enable udp2raw-c-${config_name} service.${NC}"
        return 1
    fi

    echo -e "\e[92mLocal Server (IR) configuration '${config_name}' has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling ALL UDP2RAW configurations and binaries, Please wait ...${NC}"
    echo ""
    echo ""
    display_fancy_progress 20

    # Stop and disable all udp2raw server services
    for service_file in $(systemctl list-unit-files udp2raw-s-*.service --no-legend | awk '{print $1}'); do
        echo -e "${YELLOW}Stopping and disabling ${service_file}...${NC}"
        systemctl stop "${service_file}" > /dev/null 2>&1
        systemctl disable "${service_file}" > /dev/null 2>&1
        rm -f "/etc/systemd/system/${service_file}" > /dev/null 2>&1
        echo -e "${GREEN}${service_file} stopped, disabled, and removed.${NC}"
    done

    # Stop and disable all udp2raw client services
    for service_file in $(systemctl list-unit-files udp2raw-c-*.service --no-legend | awk '{print $1}'); do
        echo -e "${YELLOW}Stopping and disabling ${service_file}...${NC}"
        systemctl stop "${service_file}" > /dev/null 2>&1
        systemctl disable "${service_file}" > /dev/null 2>&1
        rm -f "/etc/systemd/system/${service_file}" > /dev/null 2>&1
        echo -e "${GREEN}${service_file} stopped, disabled, and removed.${NC}"
    done
    
    rm -f /root/udp2raw_amd64 > /dev/null 2>&1
    
    systemctl daemon-reload > /dev/null 2>&1
    
    sleep 2
    echo ""
    echo ""
    echo -e "${GREEN}All UDP2RAW configurations and binaries have been uninstalled.${NC}"
}

menu_status() {
    echo ""
    echo -e "${CYAN}--- EU Server (Remote) Configurations Status ---${NC}"
    local s_services_found=0
    for service_file in $(systemctl list-units udp2raw-s-*.service --all --no-legend | awk '{print $1}'); do
        s_services_found=1
        if systemctl is-active --quiet "${service_file}"; then
            echo -e "\e[36m ${CYAN}Config (${service_file})${NC} > ${GREEN}Running.${NC}"
        else
            local status_output=$(systemctl status "${service_file}" | grep "Active:")
            echo -e "\e[36m ${CYAN}Config (${service_file})${NC} > ${RED}Not running. Status: ${status_output}${NC} ${YELLOW}(Check logs with option 4)${NC}"
        fi
    done
    if [ $s_services_found -eq 0 ]; then
        echo -e "${YELLOW}No EU Server (udp2raw-s-*) configurations found.${NC}"
    fi

    echo ""
    echo -e "${CYAN}--- IR Server (Local) Configurations Status ---${NC}"
    local c_services_found=0
    for service_file in $(systemctl list-units udp2raw-c-*.service --all --no-legend | awk '{print $1}'); do
        c_services_found=1
        if systemctl is-active --quiet "${service_file}"; then
            echo -e "\e[36m ${CYAN}Config (${service_file})${NC} > ${GREEN}Running.${NC}"
        else
            local status_output=$(systemctl status "${service_file}" | grep "Active:")
            echo -e "\e[36m ${CYAN}Config (${service_file})${NC} > ${RED}Not running. Status: ${status_output}${NC} ${YELLOW}(Check logs with option 4)${NC}"
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
    # local service_descriptions=() # Not strictly needed if just listing
    local counter=1

    echo -e "\n${YELLOW}Available Configurations:${NC}"
    
    local s_found=0
    # List EU services
    for service_file in $(systemctl list-units udp2raw-s-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (EU Server)"
        counter=$((counter + 1))
        s_found=1
    done

    local c_found=0
    # List IR services
    for service_file in $(systemctl list-units udp2raw-c-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (IR Server)"
        counter=$((counter + 1))
        c_found=1
    done

    if [ $s_found -eq 0 ] && [ $c_found -eq 0 ]; then
        echo -e "  ${RED}No configurations found.${NC}"
        press_enter
        return
    fi

    if [ ${#services_array[@]} -eq 0 ]; then
        # This case should be covered by the above, but as a safeguard:
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
        view_logs_func # Re-prompt
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

troubleshoot_config_func() {
    clear
    echo -e "${CYAN}--- Troubleshoot Configuration ---${NC}"
    
    local services_array=()
    local counter=1

    echo -e "\n${YELLOW}Available Configurations to Troubleshoot:${NC}"
    
    local s_found=0
    # List EU services
    for service_file in $(systemctl list-units udp2raw-s-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (EU Server)"
        counter=$((counter + 1))
        s_found=1
    done

    local c_found=0
    # List IR services
    for service_file in $(systemctl list-units udp2raw-c-*.service --all --no-legend --plain | awk '{print $1}'); do
        services_array+=("$service_file")
        echo -e "  ${GREEN}$counter)${NC} $service_file (IR Server)"
        counter=$((counter + 1))
        c_found=1
    done

    if [ $s_found -eq 0 ] && [ $c_found -eq 0 ]; then
        echo -e "  ${RED}No configurations found to troubleshoot.${NC}"
        press_enter
        return
    fi

    if [ ${#services_array[@]} -eq 0 ]; then
        # This case should be covered by the above, but as a safeguard:
        echo -e "\n${RED}No configurations available.${NC}"
        press_enter
        return
    fi

    echo -e "\n${YELLOW}Enter the number of the configuration to troubleshoot, or 0 to return to menu:${NC}"
    echo -ne "${GREEN}Select an option [0-$((${#services_array[@]}))] : ${NC}"
    read choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services_array[@]} ]; then
        echo -e "\n${RED}Invalid selection.${NC}"
        press_enter
        troubleshoot_config_func # Re-prompt
        return
    fi

    if [ "$choice" -eq 0 ]; then
        return
    fi

    local selected_service_index=$((choice - 1))
    local service_to_troubleshoot="${services_array[$selected_service_index]}"

    echo -e "\n${CYAN}--- Troubleshooting: ${YELLOW}${service_to_troubleshoot}${CYAN} ---${NC}\n"
    
    echo -e "${YELLOW}1. Current Status:${NC}"
    systemctl status "${service_to_troubleshoot}" --no-pager
    echo ""

    echo -e "${YELLOW}2. Recent Logs (last 20 lines):${NC}"
    journalctl -u "${service_to_troubleshoot}" -n 20 --no-pager
    echo -e "\n${YELLOW}   For more detailed logs, use Option 4 (View Configuration Logs) from the main menu.${NC}"
    echo ""

    echo -e "${YELLOW}3. Common Troubleshooting Steps & Checks:${NC}"
    echo -e "   - ${GREEN}Parameter Mismatch:${NC} Ensure IP addresses, ports, password, and raw-mode match between client (IR) and server (EU) configurations."
    echo -e "   - ${RED}Bind Fail / Port Conflicts:${NC} If logs show '[FATAL]bind fail', the IP/Port is likely already in use or invalid."
    echo -e "     * ${YELLOW}Identify the listening IP and Port:${NC} View the service file: ${GREEN}cat /etc/systemd/system/${service_to_troubleshoot}${NC}"
    echo -e "       Look for the '-l <listen_ip>:<listen_port>' in the 'ExecStart' line."
    echo -e "     * ${YELLOW}Check if port is in use:${NC} Replace '<PORT>' with the actual port number: ${GREEN}ss -tulnp | grep ':<PORT>'${NC}"
    echo -e "       If another process is using it, stop that process or choose a different port for this udp2raw config."
    echo -e "     * ${YELLOW}Verify Listen IP:${NC} Ensure the <listen_ip> is valid for this server. Use '0.0.0.0' (IPv4) or '[::]' (IPv6) to listen on all interfaces if unsure."
    echo -e "     * For EU (server) configs (-s): The '-l <listen_ip>:<listen_port>' is where udp2raw listens for incoming raw packets."
    echo -e "     * For IR (client) configs (-c): The '-l <local_listen_ip>:<local_listen_port>' is where udp2raw listens for local application's UDP packets."
    echo -e "   - ${GREEN}Firewall:${NC} Confirm that the necessary ports are open on all relevant firewalls."
    echo -e "     * EU Server: The port specified in its '-l' option (listening for raw packets from IR) must be open."
    echo -e "     * IR Client: Ensure outbound connection to EU server's IP and listening port is allowed."
    echo -e "   - ${GREEN}Remote Server Reachability (for IR/client configs):${NC} Can the IR server connect to the EU server's IP and the udp2raw listening port?"
    echo -e "   - ${GREEN}Correct Binary:${NC} Ensure '/root/udp2raw_amd64' is the correct, executable binary."
    echo -e "   - ${GREEN}Typos:${NC} Double-check all entered configuration values for typos when setting up the tunnel."
    
    echo -e "\n${YELLOW}If the service is in a 'failed' state, the logs above or more detailed logs (Option 4) should provide specific error messages.${NC}"
    echo -e "${YELLOW}If it's 'activating (auto-restart)', it means the service is starting and then immediately crashing. Logs are crucial here.${NC}"

    press_enter
}


echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo ""
    echo -e "\e[36m 1\e[0m) \e[93mInstall UDP2RAW binary"
    echo -e "\e[36m 2\e[0m) \e[93mSet EU Tunnel"
    echo -e "\e[36m 3\e[0m) \e[93mSet IR Tunnel"  
    echo -e "\e[36m 4\e[0m) \e[93mView Configuration Logs"
    echo -e "\e[36m 5\e[0m) \e[93mTroubleshoot a Configuration"
    echo ""
    echo -e "\e[36m 6\e[0m) \e[93mUninstall UDP2RAW"
    echo -e "\e[36m 0\e[0m) \e[93mExit"
    echo ""
    echo ""
    echo -ne "\e[92mSelect an option \e[31m[\e[97m0-6\e[31m]: \e[0m"
    read choice

    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) view_logs_func;;
        5) troubleshoot_config_func;;
        6) uninstall;;
        0) echo -e "\n ${RED}Exiting...${NC}"
            exit 0;;
        *) echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}";;
    esac

    press_enter
done
