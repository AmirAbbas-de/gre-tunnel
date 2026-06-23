# 🚀 Automated GRE Tunnel & 3x-ui Panel Setup

An interactive, production-ready Bash script to establish a secure **GRE Tunnel** between an **Iran Server (Local)** and a **Foreign Server (Remote/Kharj)**. It automates policy routing, firewall rules, persistent boot configurations, and deploys the latest `3x-ui` panel onto the Iran server with proper traffic tagging.

---

## ⚡ Quick Start (One-Liner Command)

Run the exact same command on **both** servers. The interactive script will guide you through the setup.

```bash
bash <(curl -Ls https://raw.githubusercontent.com/AmirAbbas-de/gre-tunnel/main/tunnel.sh)
```
🛠️ Deployment Workflow
For a proper setup, always execute the script on the Iran Server first, then proceed to the Foreign Server.

Step 1: Iran Server Configuration
Run the one-liner script.

Select Option 1 (Configure Iran Server).

Provide the Public IPs as prompted.

(Optional) Customize the tunnel interface name (e.g., gre1) and internal subnet (e.g., 10.10.10).

Automated Tasks performed:

Auto-detects the core outbound active network interface (supports eth0, ens3, ens18, etc.).

Creates safe system backups of modified configuration maps.

Sets up the tunnel interface and locks the internal node to ${SUBNET}.1.

Enforces boot persistence via /etc/rc.local.

Maps routing table 100 alongside structural iptables rules (fwmark 1).

Spawns the 3x-ui core installation process.

Step 2: Foreign (Kharj) Server Configuration
Run the exact same one-liner script.

Select Option 2 (Configure Foreign Server).

Provide the matching public IP addresses and tunnel variables.

Automated Tasks performed:

Establishes the exit-node side of the tunnel interface locked to ${SUBNET}.2.

Unlocks kernel layer net.ipv4.ip_forward=1 and registers it inside /etc/sysctl.conf.

Executes full outward MASQUERADE NAT on the active network interface.

Integrates iptables-persistent to prevent routing rule wipes during system updates or reboots.

🌐 3x-ui Panel Configuration Reference
Once the panel installation is finished on your Iran Server, you need to mark your proxy outbounds to go through the GRE tunnel:

Access your 3x-ui Web Panel.

Navigate to Panel Settings ➡️ Xray Configuration ➡️ Outbounds.

Replace your default freedom outbound block (tagged as direct) with this structure:

JSON
{
  "protocol": "freedom",
  "settings": {},
  "tag": "direct",
  "streamSettings": {
    "sockopt": {
      "mark": 1
    }
  }
}
🔍 Troubleshooting & Verification
If you experience connectivity issues, check the tunnel layer by running these basic diagnostic diagnostics:

1. Test Internal Tunnel Ping
From the Iran Server, attempt to ping the Foreign Server's internal tunnel interface endpoint:

Bash
ping -c 4 10.10.10.2
(Adjust the IP if you modified the default subnet during initialization).

2. Verify Tunnel Interface Status
Ensure the interface exists and has the correct MTU (1360) bound to it:

Bash
ip a show gre1
3. Check Policy Routing Rules
Ensure the fwmark rule is actively pointing towards your routing tables:

Bash
ip rule show
ip route show table 100
