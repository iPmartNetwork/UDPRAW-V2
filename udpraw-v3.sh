CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
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
        echo -ne "\r[${CYAN}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "▓"
            else
                echo -ne "░"
            fi
        done
        echo -ne "${GREEN}] ${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r[${CYAN}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "▓"
    done
    echo -ne "${GREEN}] 100%${NC}"
    echo
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo ""
    echo -e "${YELLOW}Ensuring all packages are suitable for your server.${NC}"
    echo ""
    echo -e "Please wait, it might take a while..."
    echo ""
    sleep 1
    display_fancy_progress 20
    apt-get update > /dev/null 2>&1
    echo ""

    # Ensure jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        apt-get install -y jq > /dev/null 2>&1
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}Failed to install jq. Please install it manually using 'apt-get install jq' and try again.${NC}"
            return 1
        fi
    fi

    system_architecture=$(uname -m)
    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo -e "${RED}Unsupported architecture: $system_architecture${NC}"
        exit 1
    fi

    echo ""
    echo -e "${YELLOW}Fetching the latest udp2raw release...${NC}"
    latest_release=$(curl -s https://api.github.com/repos/wangyu-/udp2raw/releases/latest | jq -r '.tag_name')
    if [ -z "$latest_release" ]; then
        echo -e "${RED}Failed to fetch the latest release. Please check your internet connection.${NC}"
        return 1
    fi
    echo -e "${GREEN}Latest release: ${MAGENTA}$latest_release${NC}"

    # Determine the binary file based on architecture
    binary_file="udp2raw_binaries.tar.gz"
    download_url="https://github.com/wangyu-/udp2raw/releases/download/$latest_release/$binary_file"

    echo ""
    echo -e "${YELLOW}Downloading udp2raw binaries...${NC}"
    if ! curl -L -o "$binary_file" "$download_url"; then
        echo -e "${RED}Failed to download udp2raw binaries. Please check your internet connection.${NC}"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}Extracting binaries...${NC}"
    if ! tar -xzf "$binary_file"; then
        echo -e "${RED}Failed to extract binaries. Please check the tarball.${NC}"
        rm -f "$binary_file"
        return 1
    fi
    rm -f "$binary_file"

    chmod +x udp2raw_amd64 udp2raw_x86

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
    local is_eu_wireguard="$2"  # New parameter to indicate if it's EU Wireguard port
    
    # Check if port is a valid number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Port must be a number.${NC}"
        return 1
    fi
    
    # Check if port is in valid range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}Port must be between 1-65535.${NC}"
        return 1
    fi
    
    # Skip Wireguard check for EU Wireguard port
    if [ "$is_eu_wireguard" != "eu_wireguard" ]; then
        # Check if port is used by WireGuard
        local wireguard_port=""
        if [ -d "/etc/wireguard" ]; then
            wireguard_port=$(awk -F'=' '/ListenPort/ {gsub(/ /,"",$2); print $2}' /etc/wireguard/*.conf 2>/dev/null)
            
            # Ensure wireguard_port is treated as an integer
            if [[ "$wireguard_port" =~ ^[0-9]+$ ]] && [ "$port" -eq "$wireguard_port" ]; then
                echo -e "${RED}Port $port is already used by WireGuard. Please choose another port.${NC}"
                return 1
            fi
        fi

        # Check if port is in use
        if ss -tuln | grep -q ":$port "; then
            echo -e "${RED}Port $port is already in use. Please choose another port.${NC}"
            return 1
        fi
    fi

    return 0
}

remote_func() {
    clear
    echo ""
    echo -e "\e[33mSelect EU Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="[::]"
            ;;
        2)
            tunnel_mode="0.0.0.0"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            remote_func
            return
            ;;
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
        # Pass "eu_wireguard" flag to skip port usage validation for Wireguard port in EU setup
        if validate_port "$remote_port" "eu_wireguard"; then
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
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            remote_func
            return
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    # Create service file
    cat << EOF > /etc/systemd/system/udp2raw-s.service
[Unit]
Description=udp2raw-s Service
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    # Start and enable service with error handling
    if ! systemctl restart "udp2raw-s.service"; then
        echo -e "${RED}Failed to start udp2raw-s service. Check the logs with: journalctl -u udp2raw-s.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-s.service"; then
        echo -e "${RED}Failed to enable udp2raw-s service.${NC}"
        return 1
    fi
    
    sleep 1

    echo -e "\e[92mRemote Server (EU) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

local_func() {
    clear
    echo ""
    echo -e "\e[33mSelect IR Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read tunnel_mode

    case $tunnel_mode in
        1)
            tunnel_mode="IPV6"
            ;;
        2)
            tunnel_mode="IPV4"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            local_func
            return
            ;;
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
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            local_func
            return
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    # Set the ExecStart command based on tunnel mode
    if [ "$tunnel_mode" == "IPV4" ]; then
        exec_start="/root/udp2raw_amd64 -c -l 0.0.0.0:${local_port} -r ${remote_address}:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    else
        exec_start="/root/udp2raw_amd64 -c -l [::]:${local_port} -r [${remote_address}]:${remote_port} -k ${password} --raw-mode ${raw_mode} -a"
    fi

    # Create service file
    cat << EOF > /etc/systemd/system/udp2raw-c.service
[Unit]
Description=udp2raw-c Service
After=network.target

[Service]
ExecStart=${exec_start}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    # Start and enable service with error handling
    if ! systemctl restart "udp2raw-c.service"; then
        echo -e "${RED}Failed to start udp2raw-c service. Check the logs with: journalctl -u udp2raw-c.service${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "udp2raw-c.service"; then
        echo -e "${RED}Failed to enable udp2raw-c service.${NC}"
        return 1
    fi

    echo -e "\e[92mLocal Server (IR) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling UDP2RAW, Please wait ...${NC}"
    echo ""
    echo ""
    display_fancy_progress 20

    # Stop and disable services
    systemctl stop "udp2raw-s.service" > /dev/null 2>&1
    systemctl disable "udp2raw-s.service" > /dev/null 2>&1
    systemctl stop "udp2raw-c.service" > /dev/null 2>&1
    systemctl disable "udp2raw-c.service" > /dev/null 2>&1
    
    # Remove service files and binaries
    rm -f /etc/systemd/system/udp2raw-s.service > /dev/null 2>&1
    rm -f /etc/systemd/system/udp2raw-c.service > /dev/null 2>&1
    rm -f /root/udp2raw_amd64 > /dev/null 2>&1
    rm -f /root/udp2raw_x86 > /dev/null 2>&1
    
    # Reload systemd
    systemctl daemon-reload > /dev/null 2>&1
    
    sleep 2
    echo ""
    echo ""
    echo -e "${GREEN}UDP2RAW has been uninstalled.${NC}"
}

menu_status() {
    systemctl is-active "udp2raw-s.service" &> /dev/null
    remote_status=$?

    systemctl is-active "udp2raw-c.service" &> /dev/null
    local_status=$?

    echo ""
    if [ $remote_status -eq 0 ]; then
        echo -e "\e[36m ${CYAN}EU Server Status${NC} > ${GREEN}Wireguard Tunnel is running.${NC}"
    else
        echo -e "\e[36m ${CYAN}EU Server Status${NC} > ${RED}Wireguard Tunnel is not running.${NC}"
    fi
    echo ""
    if [ $local_status -eq 0 ]; then
        echo -e "\e[36m ${CYAN}IR Server Status${NC} > ${GREEN}Wireguard Tunnel is running.${NC}"
    else
        echo -e "\e[36m ${CYAN}IR Server Status${NC} > ${RED}Wireguard Tunnel is not running.${NC}"
    fi
}

configure_tunnel() {
    local tunnel_name="$1"
    local service_file="/etc/systemd/system/udp2raw-${tunnel_name}.service"

    echo ""
    echo -e "\e[33mConfiguring Tunnel: ${CYAN}${tunnel_name}${NC}"
    echo ""
    echo -e "\e[33mSelect Tunnel Mode${NC}"
    echo ""
    echo -e "${RED}1${NC}. ${YELLOW}IPV6${NC}"
    echo -e "${RED}2${NC}. ${YELLOW}IPV4${NC}"
    echo ""
    echo -ne "Enter your choice [1-2] : ${NC}"
    read ip_mode

    case $ip_mode in
        1)
            ip_mode="[::]"
            ;;
        2)
            ip_mode="0.0.0.0"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            configure_tunnel "$tunnel_name"
            return
            ;;
    esac

    echo ""
    echo -e "\e[33mEnter the Local server ports (comma-separated, e.g., 443,444,445)${NC}"
    echo -ne "\e[92m[Default: 443]: ${NC}"
    read local_ports
    if [ -z "$local_ports" ]; then
        local_ports="443"
    fi

    echo ""
    echo -e "\e[33mEnter the Remote server ports (comma-separated, e.g., 40600,40601,40602)${NC}"
    echo -ne "\e[92m[Default: 40600]: ${NC}"
    read remote_ports
    if [ -z "$remote_ports" ]; then
        remote_ports="40600"
    fi

    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW \e[92m[This will be used for this tunnel]${NC}: "
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
        1)
            raw_mode="udp"
            ;;
        2)
            raw_mode="faketcp"
            ;;
        3)
            raw_mode="icmp"
            ;;
        *)
            echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
            press_enter
            configure_tunnel "$tunnel_name"
            return
            ;;
    esac

    echo -e "${CYAN}Selected protocol: ${GREEN}$raw_mode${NC}"

    # Create service file for each port pair
    IFS=',' read -ra local_ports_array <<< "$local_ports"
    IFS=',' read -ra remote_ports_array <<< "$remote_ports"

    if [ "${#local_ports_array[@]}" -ne "${#remote_ports_array[@]}" ]; then
        echo -e "${RED}The number of local ports and remote ports must match.${NC}"
        return 1
    fi

    for i in "${!local_ports_array[@]}"; do
        local_port="${local_ports_array[$i]}"
        remote_port="${remote_ports_array[$i]}"

        cat << EOF >> "$service_file"
[Unit]
Description=udp2raw-${tunnel_name}-${local_port}-${remote_port} Service
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $ip_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    done

    sleep 1
    systemctl daemon-reload

    # Start and enable service with error handling
    if ! systemctl restart "udp2raw-${tunnel_name}.service"; then
        echo -e "${RED}Failed to start udp2raw-${tunnel_name} service. Check the logs with: journalctl -u udp2raw-${tunnel_name}.service${NC}"
        return 1
    fi

    if ! systemctl enable --now "udp2raw-${tunnel_name}.service"; then
        echo -e "${RED}Failed to enable udp2raw-${tunnel_name} service.${NC}"
        return 1
    fi

    echo -e "\e[92mTunnel ${CYAN}${tunnel_name}${GREEN} has been configured and started.${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow ports ${RED}${local_ports}${GREEN} on your firewall.${NC}"
}

edit_tunnel() {
    echo ""
    echo -e "\e[33mEditing Existing Tunnel${NC}"
    echo ""
    echo -ne "\e[33mEnter the name of the tunnel to edit: ${NC}"
    read tunnel_name
    local service_file="/etc/systemd/system/udp2raw-${tunnel_name}.service"

    if [ ! -f "$service_file" ]; then
        echo -e "${RED}Tunnel ${tunnel_name} does not exist.${NC}"
        return
    fi

    echo -e "${YELLOW}Editing tunnel: ${CYAN}${tunnel_name}${NC}"
    configure_tunnel "$tunnel_name"
}

multi_tunnel() {
    clear
    echo ""
    echo -e "${YELLOW}Multi-Tunnel Configuration${NC}"
    echo ""

    while true; do
        echo -ne "\e[33mEnter a unique name for the tunnel (or type 'done' to finish): ${NC}"
        read tunnel_name
        if [ "$tunnel_name" == "done" ]; then
            break
        fi
        if [ -z "$tunnel_name" ]; then
            echo -e "${RED}Tunnel name cannot be empty. Please enter a valid name.${NC}"
            continue
        fi
        configure_tunnel "$tunnel_name"
    done
}

# Main menu loop
echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo ""
    echo -e "${BLUE} 1${NC}) ${YELLOW}Install UDP2RAW binary"
    echo -e "${BLUE} 2${NC}) ${YELLOW}Set EU Tunnel"
    echo -e "${BLUE} 3${NC}) ${YELLOW}Set IR Tunnel"
    echo -e "${BLUE} 4${NC}) ${YELLOW}Configure Multiple Tunnels"
    echo -e "${BLUE} 5${NC}) ${YELLOW}Edit Existing Tunnel"
    echo ""
    echo -e "${BLUE} 6${NC}) ${YELLOW}Uninstall UDP2RAW"
    echo -e "${BLUE} 0${NC}) ${YELLOW}Exit"
    echo ""
    echo ""
    echo -ne "${GREEN}Select an option ${RED}[${MAGENTA}0-6${RED}]: ${NC}"
    read choice

    case $choice in
        1)
            install
            ;;
        2)
            remote_func
            ;;
        3)
            local_func
            ;;
        4)
            multi_tunnel
            ;;
        5)
            edit_tunnel
            ;;
        6)
            uninstall
            ;;
        0)
            echo -e "\n ${RED}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}"
            ;;
    esac

    press_enter
done
