#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mError: Please run this script as root (sudo).\e[0m"
  exit 1
fi

# Color definitions for output
GREEN='\e[32m'
RED='\e[31m'
NC='\e[0m'
YELLOW='\e[33m'
CYAN='\e[36m'

echo -e "${GREEN}=== Enterprise GRE Tunnel & 3x-ui Automatic Script ===${NC}"

# ==========================================
# 1. DEPENDENCY CHECK & INSTALLATION
# ==========================================
echo -e "${GREEN}[+] Verifying system core dependencies...${NC}"
REQUIRED_PKGS=("curl" "iptables" "iproute2" "iputils-ping")
UPDATED=false

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -q " $pkg " && ! command -v $pkg &> /dev/null; then
        if [ "$UPDATED" = false ]; then
            echo -e "${YELLOW}[!] Updating package lists...${NC}"
            apt-get update -y > /dev/null 2>&1
            UPDATED=true
        fi
        echo -e "${YELLOW}[+] Installing missing dependency: $pkg...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y $pkg > /dev/null 2>&1
    fi
done

# ==========================================
# 2. AUTOMATIC IP & INTERFACE DETECTION
# ==========================================
echo -e "${GREEN}[+] Detecting local environment network layers...${NC}"
LOCAL_PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)

if [ -z "$LOCAL_PUBLIC_IP" ]; then
    echo -e "${RED}[!] Warning: Could not automatically detect local Public IP. Falling back to manual prompt.${NC}"
    read -p "Enter THIS server's Public IP: " LOCAL_PUBLIC_IP
else
    echo -e "${GREEN}[+] Detected Local Public IP: $LOCAL_PUBLIC_IP${NC}"
fi

MAIN_INTF=$(ip route show | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTF" ]; then
    MAIN_INTF="eth0"
fi
echo -e "${GREEN}[+] Detected primary network interface: $MAIN_INTF${NC}"

# Menu Selection
echo -e "\n${CYAN}Please choose an operation mode:${NC}"
echo "1) Configure Iran Server"
echo "2) Configure Foreign (Kharj) Server"
echo "3) Uninstall / Clean up configurations"
read -p "Select an option (1, 2, or 3): " MAIN_OPTION

# Global configuration defaults
INTERFACE_DEFAULT="gre1"
SUBNET_DEFAULT="10.10.10"

# Cleanup function block
reset_tunnel_layers() {
    local intf=$1
    echo -e "${YELLOW}[+] Tearing down network interface ${intf}...${NC}"
    ip link set $intf down 2>/dev/null
    ip tunnel del $intf 2>/dev/null
    ip rule del fwmark 1 lookup 100 2>/dev/null
    ip route flush table 100 2>/dev/null
}

# ==========================================
# OPTION 1: CONFIGURE IRAN SERVER
# ==========================================
if [ "$MAIN_OPTION" == "1" ]; then
    IP_IRAN=$LOCAL_PUBLIC_IP
    read -p "Enter REMOTE FOREIGN (Kharj) Server Public IP: " IP_KHARJ

    if [ -z "$IP_KHARJ" ]; then
        echo -e "${RED}Error: Remote Foreign IP is required.${NC}"
        exit 1
    fi

    read -p "Enter Tunnel Interface Name [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    read -p "Enter Tunnel Subnet Base [default: 10.10.10]: " SUBNET_BASE
    SUBNET_BASE=${SUBNET_BASE:-$SUBNET_DEFAULT}

    TUNNEL_IRAN_IP="${SUBNET_BASE}.1"
    TUNNEL_KHARJ_IP="${SUBNET_BASE}.2"

    echo -e "${GREEN}[+] Mitigating IPv6 structural leaks...${NC}"
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null

    [ -f /etc/rc.local ] && cp /etc/rc.local /etc/rc.local.bak
    
    reset_tunnel_layers $INTERFACE
    ip tunnel add $INTERFACE mode gre remote $IP_KHARJ local $IP_IRAN ttl 255
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu 1360
    ip addr add ${TUNNEL_IRAN_IP}/30 dev $INTERFACE
    
    echo -e "${GREEN}[+] Configuring persistence via rc.local...${NC}"
    cat << EOF > /etc/rc.local
#!/bin/bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null
ip link set $INTERFACE down 2>/dev/null
ip tunnel del $INTERFACE 2>/dev/null
ip tunnel add $INTERFACE mode gre remote $IP_KHARJ local $IP_IRAN ttl 255
ip link set $INTERFACE up
ip link set dev $INTERFACE mtu 1360
ip addr add ${TUNNEL_IRAN_IP}/30 dev $INTERFACE
exit 0
EOF
    chmod +x /etc/rc.local
    
    echo -e "${GREEN}[+] Applying Policy Routing and Iptables Mangle rules...${NC}"
    ip rule add fwmark 1 lookup 100 2>/dev/null
    ip route add default dev $INTERFACE table 100 2>/dev/null
    
    iptables -t mangle -D PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1 2>/dev/null
    iptables -t mangle -D PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1 2>/dev/null
    iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null
    
    iptables -t mangle -A PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1
    iptables -t mangle -A PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    
    echo -e "${GREEN}[+] Installing 3x-ui panel...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    
    echo -e "${GREEN}=== Iran Server Configuration Complete ===${NC}"
    
    # Verification
    echo -e "\n${YELLOW}🔍 Running Automated Verification...${NC}"
    if ping -c 3 -W 2 ${TUNNEL_KHARJ_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel end-to-end connectivity test passed!${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Foreign internal IP (${TUNNEL_KHARJ_IP}) yet.${NC}"
        echo -e "${YELLOW}This is normal if Option 2 hasn't been executed on the Foreign Node yet.${NC}"
    fi

    # Live Monitoring Option
    read -p "Would you like to monitor live traffic over this tunnel interface? (y/n): " WATCH_FLOW
    if [[ "$WATCH_FLOW" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Monitoring traffic metrics on $INTERFACE. Press Ctrl+C to exit.${NC}"
        sleep 1
        watch -n 1 "ip -s link show $INTERFACE"
    fi

# ==========================================
# OPTION 2: CONFIGURE FOREIGN SERVER
# ==========================================
elif [ "$MAIN_OPTION" == "2" ]; then
    IP_KHARJ=$LOCAL_PUBLIC_IP
    read -p "Enter REMOTE IRAN Server Public IP: " IP_IRAN

    if [ -z "$IP_IRAN" ]; then
        echo -e "${RED}Error: Remote Iran Public IP is required.${NC}"
        exit 1
    fi

    read -p "Enter Tunnel Interface Name [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    read -p "Enter Tunnel Subnet Base [default: 10.10.10]: " SUBNET_BASE
    SUBNET_BASE=${SUBNET_BASE:-$SUBNET_DEFAULT}

    TUNNEL_IRAN_IP="${SUBNET_BASE}.1"
    TUNNEL_KHARJ_IP="${SUBNET_BASE}.2"

    echo -e "${GREEN}[+] Configuring Foreign (Kharj) Server...${NC}"
    
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    reset_tunnel_layers $INTERFACE
    ip tunnel add $INTERFACE mode gre remote $IP_IRAN local $IP_KHARJ ttl 255
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu 1360
    ip addr add ${TUNNEL_KHARJ_IP}/30 dev $INTERFACE
    
    echo -e "${GREEN}[+] Enabling IP Forwarding...${NC}"
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    echo -e "${GREEN}[+] Setting up NAT and ensuring firewall persistence...${NC}"
    iptables -t nat -D POSTROUTING -o $MAIN_INTF -j MASQUERADE 2>/dev/null
    iptables -t nat -A POSTROUTING -o $MAIN_INTF -j MASQUERADE
    
    if [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get install iptables-persistent -y > /dev/null 2>&1
        iptables-save > /etc/iptables/rules.v4
    fi
    
    echo -e "${GREEN}=== Foreign Server Configuration Complete ===${NC}"
    
    # Verification
    echo -e "\n${YELLOW}🔍 Running Automated Verification...${NC}"
    if ping -c 3 -W 2 ${TUNNEL_IRAN_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel end-to-end connectivity test passed!${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Iran internal IP (${TUNNEL_IRAN_IP}) yet.${NC}"
    fi

    # Live Monitoring Option
    read -p "Would you like to monitor live NAT routing traffic packets? (y/n): " WATCH_FLOW
    if [[ "$WATCH_FLOW" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Monitoring structural NAT rules and pack counters. Press Ctrl+C to exit.${NC}"
        sleep 1
        watch -n 1 "iptables -t nat -L POSTROUTING -n -v"
    fi

# ==========================================
# OPTION 3: UNINSTALL / CLEANUP SUBMENU
# ==========================================
elif [ "$MAIN_OPTION" == "3" ]; then
    echo -e "\n${RED}=== Uninstall / Cleanup Submenu ===${NC}"
    echo "1) Cleanup Iran Server (Remove Tunnel, Routing, IPv6 modifications, and 3x-ui)"
    echo "2) Cleanup Foreign (Kharj) Server (Remove Tunnel, sysctl modifications, and NAT rules)"
    read -p "Select server environment to wipe (1 or 2): " UNINSTALL_TYPE

    read -p "Enter Tunnel Interface Name to remove [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    if [ "$UNINSTALL_TYPE" == "1" ]; then
        echo -e "${YELLOW}[+] Initiating Iran Server Cleanup...${NC}"
        
        reset_tunnel_layers $INTERFACE
        
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null

        iptables -t mangle -D PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1 2>/dev/null
        iptables -t mangle -D PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1 2>/dev/null
        iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null
        
        if [ -f /etc/rc.local.bak ]; then
            mv /etc/rc.local.bak /etc/rc.local
            echo -e "${GREEN}[+] Restored original /etc/rc.local backup.${NC}"
        else
            rm -f /etc/rc.local
            echo -e "${YELLOW}[+] Removed /etc/rc.local script mapping blocks.${NC}"
        fi
        
        if [ -f /usr/local/x-ui/x-ui ]; then
            echo -e "${YELLOW}[+] Uninstalling 3x-ui Panel system blocks...${NC}"
            x-ui stop 2>/dev/null
            systemctl disable x-ui 2>/dev/null
            rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui
        fi
        echo -e "${GREEN}=== Iran Server Cleanup Finished Successfully ===${NC}"

    elif [ "$UNINSTALL_TYPE" == "2" ]; then
        echo -e "${YELLOW}[+] Initiating Foreign Server Cleanup...${NC}"
        
        reset_tunnel_layers $INTERFACE
        iptables -t nat -D POSTROUTING -o $MAIN_INTF -j MASQUERADE 2>/dev/null
        
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-save > /etc/iptables/rules.v4
        fi
        
        if [ -f /etc/sysctl.conf.bak ]; then
            mv /etc/sysctl.conf.bak /etc/sysctl.conf
            sysctl -p /etc/sysctl.conf > /dev/null 2>&1
            echo -e "${GREEN}[+] Restored original core sysctl parameters.${NC}"
        fi
        echo -e "${GREEN}=== Foreign Server Cleanup Finished Successfully ===${NC}"
    else
        echo -e "${RED}Invalid uninstall selection. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
fi
