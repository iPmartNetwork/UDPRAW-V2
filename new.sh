CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
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
                echo -ne "▓"
            else
                echo -ne "░"
            fi
        done
        echo -ne "${YELLOW}] ${progress}%${NC}"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r[${YELLOW}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne "#"
    done
    echo -ne "${YELLOW}] ${progress}%${NC}"
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
    apt-get update -y > /dev/null 2>&1
    apt-get upgrade -y > /dev/null 2>&1
    display_fancy_progress 20
    echo ""
    system_architecture=$(uname -m)

    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo -e "${RED}Unsupported architecture: $system_architecture${NC}"
        exit 1
    fi

    sleep 1
    echo ""
    echo -e "${YELLOW}Downloading and installing udp2raw for architecture: $system_architecture${NC}"
    
    if ! curl -L -o udp2raw_amd64 https://github.com/amirmbn/UDP2RAW/raw/main/Core/udp2raw_amd64; then
        echo -e "${RED}Failed to download udp2raw_amd64. Please check your internet connection.${NC}"
        return 1
    fi
    
    sleep 1

    chmod +x udp2raw_amd64

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
        1) tunnel_mode="[::]";;
        2) tunnel_mode="0.0.0.0";;
        *) echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            remote_func
            return;;
    esac

    while true; do
        echo -ne "\e[33mEnter the port for UDP2RAW to listen on (EU Server, for incoming IR connections) \e[92m[Default: 443]${NC}: "
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
        echo -ne "\e[33mEnter the local WireGuard port on this server (EU Server, destination for UDP2RAW) \e[92m[Default: 40600]${NC}: "
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

    local service_name="udp2raw-s-${local_port}.service"

    cat << EOF > /etc/systemd/system/${service_name}
[Unit]
Description=udp2raw server on port ${local_port}
After=network.target

[Service]
ExecStart=/root/udp2raw_amd64 -s -l $tunnel_mode:${local_port} -r 127.0.0.1:${remote_port} -k "${password}" --raw-mode ${raw_mode} -a
Restart=always
User=root # Added for clarity, though system services run as root by default

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    if ! systemctl restart "${service_name}"; then
        echo -e "${RED}Failed to start ${service_name}. Check the logs with: journalctl -u ${service_name}${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "${service_name}"; then
        echo -e "${RED}Failed to enable ${service_name}.${NC}"
        return 1
    fi
    
    sleep 1

    echo -e "\e[92mRemote Server (EU) configuration for port ${local_port} has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow UDP2RAW listening port ${RED}$local_port${GREEN} on your firewall: ${RED}ufw allow $local_port ${NC}"
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
        1) tunnel_mode="IPV6";;
        2) tunnel_mode="IPV4";;
        *) echo -e "${RED}Invalid choice, choose correctly (1 or 2)...${NC}"
            press_enter
            local_func
            return;;
    esac
    
    while true; do
        echo -ne "\e[33mEnter the remote UDP2RAW listening port on EU server \e[92m[Default: 443]${NC}: "
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
        echo -ne "\e[33mEnter the local listening port for applications on this server (IR Server) \e[92m[Default: 40600]${NC}: "
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

    local service_name="udp2raw-c-${local_port}.service"

    cat << EOF > /etc/systemd/system/${service_name}
[Unit]
Description=udp2raw client for local port ${local_port} to ${remote_address}:${remote_port}
After=network.target

[Service]
ExecStart=${exec_start}
Restart=always
User=root # Added for clarity

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    
    if ! systemctl restart "${service_name}"; then
        echo -e "${RED}Failed to start ${service_name}. Check the logs with: journalctl -u ${service_name}${NC}"
        return 1
    fi
    
    if ! systemctl enable --now "${service_name}"; then
        echo -e "${RED}Failed to enable ${service_name}.${NC}"
        return 1
    fi

    echo -e "\e[92mLocal Server (IR) configuration for local port ${local_port} has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}If other devices need to access this tunnel via this IR server, allow local listening port ${RED}$local_port${GREEN} on firewall: ${RED}ufw allow $local_port ${NC}"
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling UDP2RAW, Please wait ...${NC}"
    echo ""
    display_fancy_progress 10 # Reduced time for quicker feedback

    echo -e "${YELLOW}Stopping and disabling UDP2RAW server instances...${NC}"
    systemctl list-unit-files --full -t service udp2raw-s-*.service | grep -E 'udp2raw-s-[0-9]+\.service' | awk '{print $1}' | while read srv; do
        if [ -n "$srv" ]; then
            echo -e "${CYAN}Processing $srv...${NC}"
            systemctl stop "$srv" > /dev/null 2>&1
            systemctl disable "$srv" > /dev/null 2>&1
            rm -f "/etc/systemd/system/$srv" > /dev/null 2>&1
            echo -e "${GREEN}$srv stopped, disabled, and removed.${NC}"
        fi
    done

    echo -e "${YELLOW}Stopping and disabling UDP2RAW client instances...${NC}"
    systemctl list-unit-files --full -t service udp2raw-c-*.service | grep -E 'udp2raw-c-[0-9]+\.service' | awk '{print $1}' | while read srv; do
        if [ -n "$srv" ]; then
            echo -e "${CYAN}Processing $srv...${NC}"
            systemctl stop "$srv" > /dev/null 2>&1
            systemctl disable "$srv" > /dev/null 2>&1
            rm -f "/etc/systemd/system/$srv" > /dev/null 2>&1
            echo -e "${GREEN}$srv stopped, disabled, and removed.${NC}"
        fi
    done
    
    rm -f /root/udp2raw_amd64 > /dev/null 2>&1
    echo -e "${GREEN}udp2raw binary removed.${NC}"
    
    systemctl daemon-reload > /dev/null 2>&1
    echo -e "${GREEN}Systemd daemon reloaded.${NC}"
    
    sleep 1
    echo ""
    echo -e "${GREEN}UDP2RAW has been uninstalled.${NC}"
}

menu_status() {
    echo ""
    echo -e "\e[36m ${CYAN}EU Server (udp2raw-s) Instances Status:${NC}"
    local found_s_service=0
    # Using systemctl list-units to find active services
    systemctl list-units --full --type=service --state=active --no-legend --no-pager 'udp2raw-s-*.service' | awk '{print $1}' | while read -r srv; do
        # Double check the service name format to avoid matching unrelated services if any
        if [[ "$srv" =~ ^udp2raw-s-[0-9]+\.service$ ]]; then
             echo -e "  ${GREEN}$srv is running.${NC}"
             found_s_service=1
        fi
    done
    if [ $found_s_service -eq 0 ]; then
        echo -e "  ${RED}No active EU server (udp2raw-s) instances found.${NC}"
    fi

    echo ""
    echo -e "\e[36m ${CYAN}IR Server (udp2raw-c) Instances Status:${NC}"
    local found_c_service=0
    systemctl list-units --full --type=service --state=active --no-legend --no-pager 'udp2raw-c-*.service' | awk '{print $1}' | while read -r srv; do
        if [[ "$srv" =~ ^udp2raw-c-[0-9]+\.service$ ]]; then
            echo -e "  ${GREEN}$srv is running.${NC}"
            found_c_service=1
        fi
    done
    if [ $found_c_service -eq 0 ]; then
        echo -e "  ${RED}No active IR server (udp2raw-c) instances found.${NC}"
    fi
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
    echo ""
    echo -e "\e[36m 4\e[0m) \e[93mUninstall UDP2RAW"
    echo -e "\e[36m 0\e[0m) \e[93mExit"
    echo ""
    echo ""
    echo -ne "\e[92mSelect an option \e[31m[\e[97m0-4\e[31m]: \e[0m"
    read choice

    case $choice in
        1) install;;
        2) remote_func;;
        3) local_func;;
        4) uninstall;;
        0) echo -e "\n ${RED}Exiting...${NC}"
            exit 0;;
        *) echo -e "\n ${RED}Invalid choice. Please enter a valid option.${NC}";;
    esac

    press_enter
done
