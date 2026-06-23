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

echo -e "${GREEN}=== GRE Tunnel & X-UI Automatic Setup ===${NC}"
echo "1) Configure Iran Server"
echo "2) Configure Foreign (Kharj) Server"
read -p "Select server type (1 or 2): " SERVER_TYPE

# Prompt for IP addresses
read -p "Enter IRAN Server IP: " IP_IRAN
read -p "Enter FOREIGN (Kharj) Server IP: " IP_KHARJ

# Validate IP inputs
if [ -z "$IP_IRAN" ] || [ -z "$IP_KHARJ" ]; then
    echo -e "${RED}Error: Both Iran and Foreign IPs are required.${NC}"
    exit 1
fi

# Tunnel Interface configuration variables
INTERFACE="gre1"
MTU=1360
TTL=255

# Helper function to reset existing tunnel configurations
reset_tunnel() {
    ip link set $INTERFACE down 2>/dev/null
    ip tunnel del $INTERFACE 2>/dev/null
}

if [ "$SERVER_TYPE" == "1" ]; then
    echo -e "${GREEN}[+] Configuring Iran Server...${NC}"
    
    LOCAL_IP=$IP_IRAN
    REMOTE_IP=$IP_KHARJ
    TUNNEL_IP="10.10.10.1/30"
    
    # Tear down existing configurations and create the GRE interface
    reset_tunnel
    ip tunnel add $INTERFACE mode gre remote $REMOTE_IP local $LOCAL_IP ttl $TTL
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu $MTU
    ip addr add $TUNNEL_IP dev $INTERFACE
    
    # Make the tunnel persistent across reboots via /etc/rc.local
    echo -e "${GREEN}[+] Configuring persistence via rc.local...${NC}"
    cat << EOF > /etc/rc.local
#!/bin/bash
ip link set $INTERFACE down 2>/dev/null
ip tunnel del $INTERFACE 2>/dev/null
ip tunnel add $INTERFACE mode gre remote $REMOTE_IP local $LOCAL_IP ttl $TTL
ip link set $INTERFACE up
ip link set dev $INTERFACE mtu $MTU
ip addr add $TUNNEL_IP dev $INTERFACE
exit 0
EOF
    chmod +x /etc/rc.local
    
    # Set up routing policies and iptables rules to mark and forward traffic
    echo -e "${GREEN}[+] Applying Policy Routing and Iptables rules...${NC}"
    ip rule add fwmark 1 lookup 100 2>/dev/null
    ip route add default dev $INTERFACE table 100 2>/dev/null
    
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --syn -j MARK --set-xmark 1
    iptables -t mangle -A PREROUTING -i eth0 -p udp -j MARK --set-xmark 1
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    
    # Verify tunnel creation
    ip a show $INTERFACE
    
    # Install 3x-ui panel
    echo -e "${GREEN}[+] Installing 3x-ui panel...${NC}"
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    
    echo -e "${GREEN}=== Iran Server Configuration Complete ===${NC}"
    echo -e "Panel Configuration Note: Under Xray Settings -> Outbounds, replace the 'freedom' protocol outbound block with the following JSON structure to enforce the routing mark:"
    echo -e "{\n  \"protocol\": \"freedom\",\n  \"settings\": {},\n  \"tag\": \"direct\",\n  \"streamSettings\": {\n    \"sockopt\": {\n      \"mark\": 1\n    }\n  }\n}"

elif [ "$SERVER_TYPE" == "2" ]; then
    echo -e "${GREEN}[+] Configuring Foreign (Kharj) Server...${NC}"
    
    LOCAL_IP=$IP_KHARJ
    REMOTE_IP=$IP_IRAN
    TUNNEL_IP="10.10.10.2/30"
    
    # Tear down existing configurations and create the GRE interface
    reset_tunnel
    ip tunnel add $INTERFACE mode gre remote $REMOTE_IP local $LOCAL_IP ttl $TTL
    ip link set $INTERFACE up
    ip link set dev $INTERFACE mtu $MTU
    ip addr add $TUNNEL_IP dev $INTERFACE
    
    # Verify tunnel status
    ip a show $INTERFACE
    
    # Enable IP forwarding dynamically
    echo -e "${GREEN}[+] Enabling IP Forwarding...${NC}"
    sysctl -w net.ipv4.ip_forward=1
    
    # Automate changing sysctl.conf to make IP forwarding persistent without manual nano editing
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Apply NAT masquerading to interface eth0
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    
    echo -e "${GREEN}=== Current NAT Rules on Foreign Server ===${NC}"
    iptables -t nat -L -n -v
    echo -e "${GREEN}=== Foreign Server Configuration Complete ===${NC}"

else
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
fi