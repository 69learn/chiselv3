CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m "
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
    display_fancy_progress 20
    echo ""
    system_architecture=$(uname -m)

    if [ "$system_architecture" != "x86_64" ] && [ "$system_architecture" != "amd64" ]; then
        echo "Unsupported architecture: $system_architecture"
        exit 1
    fi

    sleep 1
    echo ""
    echo -e "${YELLOW}Downloading and installing chisel for architecture: $system_architecture${NC}"
    curl -L -o chisel.gz https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_linux_amd64.gz
    gunzip chisel.gz
    chmod +x chisel
    mv chisel /usr/local/bin/

    echo ""
    echo -e "${GREEN}Chisel has been installed successfully.${NC}"
}

validate_port() {
    local port="$1"
    local exclude_ports=()
    local wireguard_port=$(awk -F'=' '/ListenPort/ {gsub(/ /,"",$2); print $2}' /etc/wireguard/*.conf)
    exclude_ports+=("$wireguard_port")

    if [[ " ${exclude_ports[@]} " =~ " $port " ]]; then
        return 0  
    fi

    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}Port $port is already in use. Please choose another port.${NC}"
        return 1
    fi

    return 0
}

remote_func() {
    clear
    echo ""
    echo -e "\e[33mSelect Tunnel Mode${NC}"
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
            echo -e "${RED}Invalid choice, choose correctly ...${NC}"
            ;;
    esac

    while true; do
        echo -ne "\e[33mEnter the Local server port \e[92m[Default: 443]${NC}: "
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
        echo -ne "\e[33mEnter the Wireguard port \e[92m[Default: 50820]${NC}: "
        read remote_port
        if [ -z "$remote_port" ]; then
            remote_port=50820
            break
        fi
        if validate_port "$remote_port"; then
            break
        fi
    done

    echo ""
    echo -ne "\e[33mEnter the Remote server address (EU) \e[92m${NC}: "
    read remote_address

    echo -ne "\e[33mEnter the User Authentication Token for Chisel \e[92m${NC}: "
    read auth_token

cat << EOF > /etc/systemd/system/chisel-server.service
[Unit]
Description=Chisel Server Service
After=network.target

[Service]
ExecStart=/usr/local/bin/chisel server --reverse --port $local_port --auth "$auth_token"

Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    systemctl restart "chisel-server.service"
    systemctl enable --now "chisel-server.service"
    systemctl start --now "chisel-server.service"
    sleep 1

    echo -e "\e[92mRemote Server (EU) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

local_func() {
    clear
    echo ""
    echo -e "\e[33mSelect Tunnel Mode${NC}"
    echo ""
    echo -ne "Enter the Remote server address (EU) \e[92m${NC}: "
    read remote_address

    echo ""
    echo -ne "\e[33mEnter the Local port \e[92m[Default: 50820]${NC}: "
    read local_port
    if [ -z "$local_port" ]; then
        local_port=50820
    fi

    echo ""
    echo -ne "\e[33mEnter the Server port \e[92m[Default: 443]${NC}: "
    read remote_port
    if [ -z "$remote_port" ]; then
        remote_port=443
    fi

    echo ""
    echo -ne "\e[33mEnter the User Authentication Token for Chisel \e[92m${NC}: "
    read auth_token

cat << EOF > /etc/systemd/system/chisel-client.service
[Unit]
Description=Chisel Client Service
After=network.target

[Service]
ExecStart=/usr/local/bin/chisel client --auth "$auth_token" $remote_address:$remote_port R:$local_port:127.0.0.1:$local_port

Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sleep 1
    systemctl daemon-reload
    systemctl restart "chisel-client.service"
    systemctl enable --now "chisel-client.service"
    systemctl start --now "chisel-client.service"

    echo -e "\e[92mLocal Server (IR) configuration has been adjusted and service started. Yours truly${NC}"
    echo ""
    echo -e "${GREEN}Make sure to allow port ${RED}$remote_port${GREEN} on your firewall by this command:${RED} ufw allow $remote_port ${NC}"
}

uninstall() {
    clear
    echo ""
    echo -e "${YELLOW}Uninstalling Chisel, Please wait ...${NC}"
    echo ""
    echo ""
    display_fancy_progress 20

    systemctl stop --now "chisel-server.service" > /dev/null 2>&1
    systemctl disable --now "chisel-server.service" > /dev/null 2>&1
    systemctl stop --now "chisel-client.service" > /dev/null 2>&1
    systemctl disable --now "chisel-client.service" > /dev/null 2>&1
    rm -f /etc/systemd/system/chisel-server.service > /dev/null 2>&1
    rm -f /etc/systemd/system/chisel-client.service > /dev/null 2>&1
    rm -f /usr/local/bin/chisel > /dev/null 2>&1
    
    sleep 2
    echo ""
   
