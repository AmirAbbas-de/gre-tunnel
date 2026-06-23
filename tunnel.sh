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

echo -e "${GREEN}=== Advanced GRE Tunnel & 3x-ui Automatic Script ===${NC}"
echo "1) Configure Iran Server"
echo "2) Configure Foreign (Kharj) Server"
echo "3) Uninstall / Clean up configurations"
read -p "Select an option (1, 2, or 3): " MAIN_OPTION

# Global configuration variables (Default Fallbacks)
INTERFACE_DEFAULT="gre1"
SUBNET_DEFAULT="10.10.10"

# Automatically detect the primary outbound network interface
MAIN_INTF=$(ip route show | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTF" ]; then
    MAIN_INTF="eth0"
fi

# Helper function to clear old tunnel configurations cleanly
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
    read -p "Enter IRAN Server Public IP: " IP_IRAN
    read -p "Enter FOREIGN (Kharj) Server Public IP: " IP_KHARJ

    if [ -z "$IP_IRAN" ] || [ -z "$IP_KHARJ" ]; then
        echo -e "${RED}Error: Both Iran and Foreign IPs are required.${NC}"
        exit 1
    fi

    read -p "Enter Tunnel Interface Name [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    read -p "Enter Tunnel Subnet Base [default: 10.10.10]: " SUBNET_BASE
    SUBNET_BASE=${SUBNET_BASE:-$SUBNET_DEFAULT}

    TUNNEL_IRAN_IP="${SUBNET_BASE}.1"
    TUNNEL_KHARJ_IP="${SUBNET_BASE}.2"

    echo -e "${GREEN}[+] Configuring Iran Server...${NC}"
    echo -e "${GREEN}[+] Detected primary network interface: $MAIN_INTF${NC}"
    
    [ -f /etc/rc.local ] && cp /etc/rc.local /etc/rc.local.bak
    
    reset_tunnel_layers $INTERFACE
    ip tunnel add $INTERFACE mode gre remote $IP_KHARJ local $IP_IRAN ttl 255
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu 1360
    ip addr add ${TUNNEL_IRAN_IP}/30 dev $INTERFACE
    
    echo -e "${GREEN}[+] Configuring persistence via rc.local...${NC}"
    cat << EOF > /etc/rc.local
#!/bin/bash
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
    
    ip a show $INTERFACE
    
    echo -e "${GREEN}[+] Installing 3x-ui panel...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    
    echo -e "${GREEN}=== Iran Server Configuration Complete ===${NC}"
    
    # Verification
    echo -e "\n${YELLOW}🔍 Running Automated Verification...${NC}"
    if ip link show $INTERFACE | grep -q "UP"; then
        echo -e "${GREEN}[PASS] Interface $INTERFACE is UP.${NC}"
    else
        echo -e "${RED}[FAIL] Interface $INTERFACE is DOWN!${NC}"
    fi

    echo -e "\n${YELLOW}[!] Testing internal tunnel ping to Foreign Server (${TUNNEL_KHARJ_IP})...${NC}"
    sleep 2
    if ping -c 3 -W 2 ${TUNNEL_KHARJ_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel connectivity test passed!${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Foreign internal IP (${TUNNEL_KHARJ_IP}) yet.${NC}"
    fi

# ==========================================
# OPTION 2: CONFIGURE FOREIGN SERVER
# ==========================================
elif [ "$MAIN_OPTION" == "1" ] || [ "$MAIN_OPTION" == "2" ]; then
    read -p "Enter IRAN Server Public IP: " IP_IRAN
    read -p "Enter FOREIGN (Kharj) Server Public IP: " IP_KHARJ

    if [ -z "$IP_IRAN" ] || [ -z "$IP_KHARJ" ]; then
        echo -e "${RED}Error: Both Iran and Foreign IPs are required.${NC}"
        exit 1
    fi

    read -p "Enter Tunnel Interface Name [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    read -p "Enter Tunnel Subnet Base [default: 10.10.10]: " SUBNET_BASE
    SUBNET_BASE=${SUBNET_BASE:-$SUBNET_DEFAULT}

    TUNNEL_IRAN_IP="${SUBNET_BASE}.1"
    TUNNEL_KHARJ_IP="${SUBNET_BASE}.2"

    echo -e "${GREEN}[+] Configuring Foreign (Kharj) Server...${NC}"
    echo -e "${GREEN}[+] Detected primary network interface: $MAIN_INTF${NC}"
    
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    reset_tunnel_layers $INTERFACE
    ip tunnel add $INTERFACE mode gre remote $IP_IRAN local $IP_KHARJ ttl 255
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu 1360
    ip addr add ${TUNNEL_KHARJ_IP}/30 dev $INTERFACE
    
    ip a show $INTERFACE
    
    echo -e "${GREEN}[+] Enabling IP Forwarding...${NC}"
    sysctl -w net.ipv4.ip_forward=1
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
        apt-get update -y && apt-get install iptables-persistent -y
        iptables-save > /etc/iptables/rules.v4
    fi
    
    echo -e "${GREEN}=== Foreign Server Configuration Complete ===${NC}"
    
    # Verification
    echo -e "\n${YELLOW}🔍 Running Automated Verification...${NC}"
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        echo -e "${GREEN}[PASS] Core IP Forwarding is active.${NC}"
    else
        echo -e "${RED}[FAIL] Core IP Forwarding is disabled!${NC}"
    fi

    echo -e "\n${YELLOW}[!] Testing internal tunnel ping to Iran Server (${TUNNEL_IRAN_IP})...${NC}"
    sleep 2
    if ping -c 3 -W 2 ${TUNNEL_IRAN_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel connectivity test passed!${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Iran internal IP (${TUNNEL_IRAN_IP}) yet.${NC}"
    fi

# ==========================================
# OPTION 3: UNINSTALL / CLEANUP SUBMENU
# ==========================================
elif [ "$MAIN_OPTION" == "3" ]; then
    echo -e "\n${RED}=== Uninstall / Cleanup Submenu ===${NC}"
    echo "1) Cleanup Iran Server (Remove Tunnel, Routing, and 3x-ui)"
    echo "2) Cleanup Foreign (Kharj) Server (Remove Tunnel and NAT rules)"
    read -p "Select server environment to wipe (1 or 2): " UNINSTALL_TYPE

    read -p "Enter Tunnel Interface Name to remove [default: gre1]: " INTERFACE
    INTERFACE=${INTERFACE:-$INTERFACE_DEFAULT}

    if [ "$UNINSTALL_TYPE" == "1" ]; then
        echo -e "${YELLOW}[+] Initiating Iran Server Cleanup...${NC}"
        
        # 1. Tear down GRE Interface and custom tables
        reset_tunnel_layers $INTERFACE
        
        # 2. Clear Iptables mangle and forwarding entries
        iptables -t mangle -D PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1 2>/dev/null
        iptables -t mangle -D PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1 2>/dev/null
        iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null
        
        # 3. Purge rc.local configuration maps safely
        if [ -f /etc/rc.local.bak ]; then
            mv /etc/rc.local.bak /etc/rc.local
            echo -e "${GREEN}[+] Restored original /etc/rc.local backup.${NC}"
        else
            rm -f /etc/rc.local
            echo -e "${YELLOW}[+] Removed /etc/rc.local interface mapping scripts.${NC}"
        fi
        
        # 4. Uninstall 3x-ui panel infrastructure natively
        if [ -f /usr/local/x-ui/x-ui ]; then
            echo -e "${YELLOW}[+] Uninstalling 3x-ui Panel system blocks...${NC}"
            x-ui stop 2>/dev/null
            systemctl disable x-ui 2>/dev/null
            rm -rf /usr/local/x-ui /etc/x-ui /usr/bin/x-ui
        fi
        
        echo -e "${GREEN}=== Iran Server Cleanup Finished Successfully ===${NC}"

    elif [ "$UNINSTALL_TYPE" == "2" ]; then
        echo -e "${YELLOW}[+] Initiating Foreign Server Cleanup...${NC}"
        
        # 1. Tear down GRE interface
        reset_tunnel_layers $INTERFACE
        
        # 2. Delete Iptables NAT Masquerade rule
        iptables -t nat -D POSTROUTING -o $MAIN_INTF -j MASQUERADE 2>/dev/null
        
        # Save updated persistent rules map if available
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-save > /etc/iptables/rules.v4
        fi
        
        # 3. Revert sysctl IP forwarding changes if a backup is found
        if [ -f /etc/sysctl.conf.bak ]; then
            mv /etc/sysctl.conf.bak /etc/sysctl.conf
            sysctl -p /etc/sysctl.conf > /dev/null
            echo -e "${GREEN}[+] Restored original sysctl configurations layer.${NC}"
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
