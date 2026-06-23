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

echo -e "${GREEN}=== Advanced GRE Tunnel & 3x-ui Automatic Setup ===${NC}"
echo "1) Configure Iran Server"
echo "2) Configure Foreign (Kharj) Server"
read -p "Select server type (1 or 2): " SERVER_TYPE

# Prompt for IP addresses
read -p "Enter IRAN Server Public IP: " IP_IRAN
read -p "Enter FOREIGN (Kharj) Server Public IP: " IP_KHARJ

if [ -z "$IP_IRAN" ] || [ -z "$IP_KHARJ" ]; then
    echo -e "${RED}Error: Both Iran and Foreign IPs are required.${NC}"
    exit 1
fi

# Dynamic Tunnel Interface & Subnet Options
read -p "Enter Tunnel Interface Name [default: gre1]: " INTERFACE
INTERFACE=${INTERFACE:-gre1}

read -p "Enter Tunnel Subnet Base (e.g., 10.10.10) [default: 10.10.10]: " SUBNET_BASE
SUBNET_BASE=${SUBNET_BASE:-10.10.10}

MTU=1360
TTL=255
TUNNEL_IRAN_IP="${SUBNET_BASE}.1"
TUNNEL_KHARJ_IP="${SUBNET_BASE}.2"

# Automatically detect the primary outbound network interface
MAIN_INTF=$(ip route show | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTF" ]; then
    MAIN_INTF="eth0" # Fallback if detection fails
fi
echo -e "${GREEN}[+] Detected primary network interface: $MAIN_INTF${NC}"

# Helper function to clear old tunnel configurations cleanly
reset_tunnel() {
    ip link set $INTERFACE down 2>/dev/null
    ip tunnel del $INTERFACE 2>/dev/null
    ip rule del fwmark 1 lookup 100 2>/dev/null
}

if [ "$SERVER_TYPE" == "1" ]; then
    echo -e "${GREEN}[+] Configuring Iran Server...${NC}"
    
    # Backup rc.local before making modifications
    [ -f /etc/rc.local ] && cp /etc/rc.local /etc/rc.local.bak
    
    reset_tunnel
    ip tunnel add $INTERFACE mode gre remote $IP_KHARJ local $IP_IRAN ttl $TTL
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu $MTU
    ip addr add ${TUNNEL_IRAN_IP}/30 dev $INTERFACE
    
    echo -e "${GREEN}[+] Configuring persistence via rc.local...${NC}"
    cat << EOF > /etc/rc.local
#!/bin/bash
ip link set $INTERFACE down 2>/dev/null
ip tunnel del $INTERFACE 2>/dev/null
ip tunnel add $INTERFACE mode gre remote $IP_KHARJ local $IP_IRAN ttl $TTL
ip link set $INTERFACE up
ip link set dev $INTERFACE mtu $MTU
ip addr add ${TUNNEL_IRAN_IP}/30 dev $INTERFACE
exit 0
EOF
    chmod +x /etc/rc.local
    
    echo -e "${GREEN}[+] Applying Policy Routing and Iptables Mangle rules...${NC}"
    ip rule add fwmark 1 lookup 100 2>/dev/null
    ip route add default dev $INTERFACE table 100 2>/dev/null
    
    # Dynamically flush existing identical rules to avoid duplicates
    iptables -t mangle -D PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1 2>/dev/null
    iptables -t mangle -D PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1 2>/dev/null
    iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null
    
    # Apply rules using the auto-detected interface
    iptables -t mangle -A PREROUTING -i $MAIN_INTF -p tcp --syn -j MARK --set-xmark 1
    iptables -t mangle -A PREROUTING -i $MAIN_INTF -p udp -j MARK --set-xmark 1
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    
    ip a show $INTERFACE
    
    echo -e "${GREEN}[+] Installing 3x-ui panel...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    
    echo -e "${GREEN}=== Iran Server Configuration Complete ===${NC}"
    
    # === BASH TROUBLESHOOTING SECTION FOR IRAN SERVER ===
    echo -e "\n${YELLOW}🔍 Running Automated Troubleshooting & Verification...${NC}"
    echo -e "Checking interface status..."
    if ip link show $INTERFACE | grep -q "UP"; then
        echo -e "${GREEN}[PASS] Interface $INTERFACE is UP with MTU $MTU.${NC}"
    else
        echo -e "${RED}[FAIL] Interface $INTERFACE is DOWN or missing!${NC}"
    fi
    
    echo -e "Checking policy routing rule..."
    if ip rule show | grep -q "fwmark 0x1 lookup 100"; then
        echo -e "${GREEN}[PASS] Policy routing for fwmark 1 is active.${NC}"
    else
        echo -e "${RED}[FAIL] Policy routing rule is missing!${NC}"
    fi

    echo -e "\n${YELLOW}[!] Testing internal tunnel ping to Foreign Server (${TUNNEL_KHARJ_IP})...${NC}"
    echo -e "Waiting 3 seconds for tunnel initialization..."
    sleep 3
    if ping -c 3 -W 2 ${TUNNEL_KHARJ_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel connectivity test passed! Ping successful.${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Foreign internal IP (${TUNNEL_KHARJ_IP}) yet.${NC}"
        echo -e "${YELLOW}Please ensure you have completed Option 2 on the Foreign server and that GRE protocol (47) is allowed in your hosting firewall.${NC}"
    fi

elif [ "$SERVER_TYPE" == "2" ]; then
    echo -e "${GREEN}[+] Configuring Foreign (Kharj) Server...${NC}"
    
    # Backup sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
    reset_tunnel
    ip tunnel add $INTERFACE mode gre remote $IP_IRAN local $IP_KHARJ ttl $TTL
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu $MTU
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
    
    # Install iptables-persistent to save NAT configurations safely
    if [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && apt-get install iptables-persistent -y
        iptables-save > /etc/iptables/rules.v4
    fi
    
    echo -e "${GREEN}=== Foreign Server Configuration Complete ===${NC}"
    
    # === BASH TROUBLESHOOTING SECTION FOR FOREIGN SERVER ===
    echo -e "\n${YELLOW}🔍 Running Automated Troubleshooting & Verification...${NC}"
    echo -e "Checking IP Forwarding status..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        echo -e "${GREEN}[PASS] Core IP Forwarding is active.${NC}"
    else
        echo -e "${RED}[FAIL] Core IP Forwarding is disabled!${NC}"
    fi

    echo -e "Checking NAT Masquerade rule..."
    if iptables -t nat -L POSTROUTING -n -v | grep -q "MASQUERADE"; then
        echo -e "${GREEN}[PASS] Iptables NAT Masquerade is active on $MAIN_INTF.${NC}"
    else
        echo -e "${RED}[FAIL] NAT Masquerade rule was not applied properly!${NC}"
    fi

    echo -e "\n${YELLOW}[!] Testing internal tunnel ping to Iran Server (${TUNNEL_IRAN_IP})...${NC}"
    echo -e "Waiting 3 seconds for tunnel initialization..."
    sleep 3
    if ping -c 3 -W 2 ${TUNNEL_IRAN_IP} > /dev/null; then
        echo -e "${GREEN}[SUCCESS] Tunnel connectivity test passed! Ping successful.${NC}"
    else
        echo -e "${RED}[WARNING] Cannot ping Iran internal IP (${TUNNEL_IRAN_IP}) yet.${NC}"
        echo -e "${YELLOW}Please ensure you have completed Option 1 on the Iran server and that GRE protocol (47) is allowed in your hosting firewall.${NC}"
    fi
else
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
fi
