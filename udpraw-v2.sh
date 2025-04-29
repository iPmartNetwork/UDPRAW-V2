#!/bin/bash

CONFIG_FILE="servers.json"
UDP2RAW_BIN="/usr/local/bin/udp2raw"

CYAN="\033[96m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
NC="\033[0m"

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root.${NC}"
    exit 1
  fi
}

install_jq_if_missing() {
  if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing 'jq'...${NC}"
    apt update -y > /dev/null 2>&1 && apt install -y jq > /dev/null 2>&1
    if ! command -v jq &> /dev/null; then
      echo -e "${RED}Failed to install jq. Please install it manually.${NC}"
      exit 1
    fi
  fi
}

show_server_info() {
  info=$(curl -s https://ipinfo.io/json)
  ip=$(echo "$info" | jq -r '.ip')
  org=$(echo "$info" | jq -r '.org')
  country=$(echo "$info" | jq -r '.country')
  city=$(echo "$info" | jq -r '.city')

  echo -e "${CYAN}========================================${NC}"
  echo -e "${GREEN}Server IP    :${NC} $ip"
  echo -e "${GREEN}Location     :${NC} $city, $country"
  echo -e "${GREEN}Provider     :${NC} $org"
  echo -e "${CYAN}========================================${NC}"
}

install_udp2raw() {
  echo -e "${YELLOW}Installing udp2raw binary from iPmartNetwork...${NC}"
  arch=$(uname -m)
  url=""

  case "$arch" in
    x86_64|amd64)
      url="https://github.com/iPmartNetwork/UDPRAW-V2/releases/latest/download/udp2raw_amd64"
      ;;
    i386|i686)
      url="https://github.com/iPmartNetwork/UDPRAW-V2/releases/latest/download/udp2raw_x86"
      ;;
    *)
      echo -e "${RED}Unsupported architecture: $arch${NC}"
      exit 1
      ;;
  esac

  curl -L -o "$UDP2RAW_BIN" "$url"
  chmod +x "$UDP2RAW_BIN"

  echo -e "${GREEN}udp2raw installed at $UDP2RAW_BIN${NC}"
}

init_config_file() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "[]" > "$CONFIG_FILE"
    echo -e "${GREEN}Initialized empty config: $CONFIG_FILE${NC}"
  fi
}

add_entry() {
  read -p "Enter unique name for this tunnel: " name
  read -p "Mode (server/client): " mode
  read -p "Listen address (0.0.0.0 or [::]): " listen
  read -p "Local port to listen on: " lport
  read -p "Tunnel port (used in -r parameter): " tunnel_port

  if [ "$mode" = "client" ]; then
    read -p "Remote address to connect to: " raddr
  else
    raddr="127.0.0.1"
  fi

  read -p "Password: " pass
  echo -e "Select protocol: 1) udp 2) faketcp 3) icmp"
  read -p "Choice [1-3]: " proto_choice

  case $proto_choice in
    1) proto="udp";;
    2) proto="faketcp";;
    3) proto="icmp";;
    *) proto="faketcp";;
  esac

  jq ". += [{\"name\": \"$name\", \"mode\": \"$mode\", \"listen\": \"$listen\", \"local_port\": $lport, \"remote_address\": \"$raddr\", \"remote_port\": $tunnel_port, \"password\": \"$pass\", \"protocol\": \"$proto\"}]" "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"

  echo -e "${GREEN}Tunnel '$name' added.${NC}"
}

delete_entry() {
  echo -e "\n${YELLOW}Available tunnels:${NC}"
  jq -r '.[] | .name' "$CONFIG_FILE" | nl -w2 -s') '
  read -p "Enter the name of the tunnel to delete: " delname
  jq "map(select(.name != \"$delname\"))" "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
  systemctl stop udp2raw-$delname.service 2>/dev/null
  systemctl disable udp2raw-$delname.service 2>/dev/null
  rm -f /etc/systemd/system/udp2raw-$delname.service
  systemctl daemon-reload
  echo -e "${GREEN}Tunnel '$delname' removed.${NC}"
}

generate_services() {
  entries=$(jq -c '.[]' "$CONFIG_FILE")
  for entry in $entries; do
    name=$(echo "$entry" | jq -r '.name')
    mode=$(echo "$entry" | jq -r '.mode')
    listen=$(echo "$entry" | jq -r '.listen')
    lport=$(echo "$entry" | jq -r '.local_port')
    raddr=$(echo "$entry" | jq -r '.remote_address')
    rport=$(echo "$entry" | jq -r '.remote_port')
    pass=$(echo "$entry" | jq -r '.password')
    proto=$(echo "$entry" | jq -r '.protocol')

    if [ "$mode" = "server" ]; then
      cmd="$UDP2RAW_BIN -s -l $listen:$lport -r $raddr:$rport -k \"$pass\" --raw-mode $proto -a"
    else
      cmd="$UDP2RAW_BIN -c -l $listen:$lport -r $raddr:$rport -k \"$pass\" --raw-mode $proto -a"
    fi

    service_file="/etc/systemd/system/udp2raw-$name.service"
    cat <<EOF > "$service_file"
[Unit]
Description=udp2raw tunnel for $name
After=network.target

[Service]
ExecStart=$cmd
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now udp2raw-$name.service
    echo -e "${GREEN}Service for '$name' created and started.${NC}"
  done
}

show_status() {
  echo -e "\n${CYAN}Tunnel Status:${NC}"
  for f in /etc/systemd/system/udp2raw-*.service; do
    [ -e "$f" ] || continue
    name=$(basename "$f" | cut -d'-' -f2- | sed 's/.service//')
    state=$(systemctl is-active "udp2raw-$name.service")
    if [ "$state" = "active" ]; then
      echo -e "${name}: ${GREEN}active${NC}"
    else
      echo -e "${name}: ${RED}inactive${NC}"
    fi
  done
}

main_menu() {
  while true; do
    clear
    show_server_info
    echo -e "${CYAN}=== UDP2RAW Multi-Tunnel Manager ===${NC}"
    echo -e "1) Install udp2raw binary"
    echo -e "2) Add new tunnel"
    echo -e "3) Delete existing tunnel"
    echo -e "4) Generate & start all tunnels"
    echo -e "5) Show status of all tunnels"
    echo -e "0) Exit"
    read -p "Choose: " choice
    case $choice in
      1) install_udp2raw;;
      2) add_entry;;
      3) delete_entry;;
      4) generate_services;;
      5) show_status;;
      0) exit;;
      *) echo -e "${RED}Invalid option${NC}";;
    esac
  done
}

check_root
install_jq_if_missing
init_config_file
main_menu
