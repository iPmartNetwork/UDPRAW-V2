CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

install() {
    clear
    echo ""
    echo -e "${YELLOW}Checking and installing the latest UDPRAW-V2 release from GitHub...${NC}"
    echo ""
    sleep 1
    # Get the latest release
    latest_url=$(curl -s https://api.github.com/repos/iPmartNetwork/UDPRAW-V2/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 | head -n1)
    if [ -z "$latest_url" ]; then
        echo -e "${RED}Error fetching download link. Please check your internet connection or the GitHub address.${NC}"
        return 1
    fi
    echo -e "${YELLOW}Downloading: $latest_url${NC}"
    curl -L -o /usr/local/bin/udpraw "$latest_url"
    chmod +x /usr/local/bin/udpraw
    echo -e "${GREEN}UDPRAW-V2 successfully installed at /usr/local/bin/udpraw.${NC}"
    # Enable IP forwarding
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
    echo -e "${GREEN}IP forwarding enabled.${NC}"
    return 0
}

validate_port() {
    local port="$1"
    
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
    
    # Check if port is used by WireGuard
    local wireguard_port=""
    if [ -d "/etc/wireguard" ]; then
        wireguard_port=$(awk -F'=' '/ListenPort/ {gsub(/ /,"",$2); print $2}' /etc/wireguard/*.conf 2>/dev/null)
        
        if [ "$port" -eq "$wireguard_port" ]; then
            echo -e "${RED}Port $port is already used by WireGuard. Please choose another port.${NC}"
            return 1
        fi
    fi

    # Check if port is in use
    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use. Please choose another port.${NC}"
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
        echo -ne "\e[33mEnter the Local server (IR) port:${NC} "
        read local_port
        if [ -z "$local_port" ]; then
            echo -e "${RED}Port cannot be empty. Please enter a port.${NC}"
            continue
        fi
        if validate_port "$local_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port:${NC} "
        read remote_port
        if [ -z "$remote_port" ]; then
            echo -e "${RED}Port cannot be empty. Please enter a port.${NC}"
            continue
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW:${NC} "
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
    while true; do
        echo -ne "Enter your choice [1-3] : ${NC}"
        read protocol_choice
        case $protocol_choice in
            1)
                raw_mode="udp"
                break
                ;;
            2)
                raw_mode="faketcp"
                break
                ;;
            3)
                raw_mode="icmp"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
                ;;
        esac
    done

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
        echo -ne "\e[33mEnter the Local server (IR) port:${NC} "
        read remote_port
        if [ -z "$remote_port" ]; then
            echo -e "${RED}Port cannot be empty. Please enter a port.${NC}"
            continue
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    while true; do
        echo ""
        echo -ne "\e[33mEnter the Wireguard port - installed on EU:${NC} "
        read local_port
        if [ -z "$local_port" ]; then
            echo -e "${RED}Port cannot be empty. Please enter a port.${NC}"
            continue
        fi
        if validate_port "$local_port"; then
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Remote server (EU) IPV6 / IPV4 (Based on your tunnel preference):${NC} "
        read remote_address
        if [ -z "$remote_address" ]; then
            echo -e "${RED}Remote address cannot be empty.${NC}"
        else
            break
        fi
    done
    
    echo ""
    while true; do
        echo -ne "\e[33mEnter the Password for UDP2RAW:${NC} "
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
    while true; do
        echo -ne "Enter your choice [1-3] : ${NC}"
        read protocol_choice
        case $protocol_choice in
            1)
                raw_mode="udp"
                break
                ;;
            2)
                raw_mode="faketcp"
                break
                ;;
            3)
                raw_mode="icmp"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice, choose correctly (1-3)...${NC}"
                ;;
        esac
    done

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

install_socat() {
    if ! command -v socat &> /dev/null; then
        echo -e "${YELLOW}Installing socat...${NC}"
        apt-get update > /dev/null 2>&1
        apt-get install -y socat > /dev/null 2>&1
        echo -e "${GREEN}socat installed.${NC}"
    fi
}

udp2tcp_server() {
    clear
    install_socat
    echo -e "${YELLOW}Configure UDP2TCP Server (EU)${NC}"
    while true; do
        echo -ne "\e[33mEnter TCP listen port (for client to connect):${NC} "
        read listen_tcp
        if [ -z "$listen_tcp" ]; then
            echo -e "${RED}Port cannot be empty.${NC}"
            continue
        fi
        if validate_port "$listen_tcp"; then
            break
        fi
    done
    while true; do
        echo -ne "\e[33mEnter local UDP port (WireGuard server):${NC} "
        read local_udp
        if [ -z "$local_udp" ]; then
            echo -e "${RED}Port cannot be empty.${NC}"
            continue
        fi
        if validate_port "$local_udp"; then
            break
        fi
    done
    cat << EOF > /etc/systemd/system/udp2tcp-server.service
[Unit]
Description=UDP2TCP Server (socat)
After=network.target

[Service]
ExecStart=/usr/bin/socat -d tcp-l:$listen_tcp,reuseaddr,keepalive,fork UDP4:127.0.0.1:$local_udp
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart udp2tcp-server.service
    systemctl enable --now udp2tcp-server.service
    echo -e "${GREEN}UDP2TCP server service started.${NC}"
}

udp2tcp_client() {
    clear
    install_socat
    echo -e "${YELLOW}Configure UDP2TCP Client (IR)${NC}"
    while true; do
        echo -ne "\e[33mEnter remote server IP (EU):${NC} "
        read remote_ip
        if [ -z "$remote_ip" ]; then
            echo -e "${RED}IP cannot be empty.${NC}"
        else
            break
        fi
    done
    while true; do
        echo -ne "\e[33mEnter remote TCP port (server listen port):${NC} "
        read remote_tcp
        if [ -z "$remote_tcp" ]; then
            echo -e "${RED}Port cannot be empty.${NC}"
            continue
        fi
        if validate_port "$remote_tcp"; then
            break
        fi
    done
    while true; do
        echo -ne "\e[33mEnter local UDP listen port (WireGuard client):${NC} "
        read local_udp
        if [ -z "$local_udp" ]; then
            echo -e "${RED}Port cannot be empty.${NC}"
            continue
        fi
        if validate_port "$local_udp"; then
            break
        fi
    done
    cat << EOF > /etc/systemd/system/udp2tcp-client.service
[Unit]
Description=UDP2TCP Client (socat)
After=network.target

[Service]
ExecStart=/usr/bin/socat -d -t600 -T600 -d UDP4-LISTEN:$local_udp tcp4:$remote_ip:$remote_tcp,keepalive
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart udp2tcp-client.service
    systemctl enable --now udp2tcp-client.service
    echo -e "${GREEN}UDP2TCP client service started.${NC}"
}

uninstall_udp2tcp() {
    systemctl stop udp2tcp-server.service > /dev/null 2>&1
    systemctl disable udp2tcp-server.service > /dev/null 2>&1
    rm -f /etc/systemd/system/udp2tcp-server.service
    systemctl stop udp2tcp-client.service > /dev/null 2>&1
    systemctl disable udp2tcp-client.service > /dev/null 2>&1
    rm -f /etc/systemd/system/udp2tcp-client.service
    systemctl daemon-reload > /dev/null 2>&1
    echo -e "${GREEN}UDP2TCP services removed.${NC}"
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

# Main menu loop
echo ""
while true; do
    clear    
    menu_status
    echo ""
    echo ""
    echo -e "${CYAN} 1${NC}) ${YELLOW}Install UDP2RAW binary"
    echo -e "${CYAN} 2${NC}) ${YELLOW}Configure EU Tunnel (Server)"
    echo -e "${CYAN} 3${NC}) ${YELLOW}Configure IR Tunnel (Client)"  
    echo -e "${CYAN} 4${NC}) ${YELLOW}Uninstall UDP2RAW"
    echo -e "${CYAN} 5${NC}) ${YELLOW}Configure UDP2TCP Server (EU)"
    echo -e "${CYAN} 6${NC}) ${YELLOW}Configure UDP2TCP Client (IR)"
    echo -e "${CYAN} 7${NC}) ${YELLOW}Uninstall UDP2TCP"
    echo -e "${CYAN} 0${NC}) ${YELLOW}Exit"
    echo ""
    echo ""
    echo -ne "${GREEN}Select an option ${RED}[0-7]: ${NC}"
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
            uninstall
            ;;
        5)
            udp2tcp_server
            ;;
        6)
            udp2tcp_client
            ;;
        7)
            uninstall_udp2tcp
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
