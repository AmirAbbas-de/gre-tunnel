# 🚀 **Automated GRE Tunnel & 3x-ui Panel Setup**

An interactive, production-ready Bash script that establishes a secure **GRE Tunnel** between an **Iran Server (Local)** and a **Foreign Server (Remote/Kharj)**. It automates policy routing, firewall rules, persistent boot configurations, and deploys the latest `3x-ui` panel onto the Iran server with proper traffic tagging.

---

## ⚡ **Quick Start (One-Liner Command)**

Run the **exact same command** on **both** servers. The interactive script will guide you through the setup.

```bash
bash <(curl -Ls https://raw.githubusercontent.com/AmirAbbas-de/gre-tunnel/main/tunnel.sh)
```

---

## 🛠️ **Deployment Workflow**

For a proper setup, always execute the script on the **Iran Server first**, then proceed to the **Foreign Server**.

### **Step 1: Iran Server Configuration**
1. Run the one-liner script.
2. Select **Option 1** (Configure Iran Server).
3. Provide the Public IPs as prompted.
4. (Optional) Customize the tunnel interface name (e.g., `gre1`) and internal subnet (e.g., `10.10.10`).

**Automated Tasks Performed:**
- ✅ Auto-detects the core outbound active network interface (supports `eth0`, `ens3`, `ens18`, etc.)
- ✅ Creates safe system backups of modified configuration maps
- ✅ Sets up the tunnel interface and locks the internal node to `${SUBNET}.1`
- ✅ Enforces boot persistence via `/etc/rc.local`
- ✅ Maps routing table `100` alongside structural iptables rules (`fwmark 1`)
- ✅ Spawns the `3x-ui` core installation process

---

### **Step 2: Foreign (Kharj) Server Configuration**
1. Run the exact same one-liner script.
2. Select **Option 2** (Configure Foreign Server).
3. Provide the matching public IP addresses and tunnel variables.

**Automated Tasks Performed:**
- ✅ Establishes the exit-node side of the tunnel interface locked to `${SUBNET}.2`
- ✅ Unlocks kernel layer `net.ipv4.ip_forward=1` and registers it inside `/etc/sysctl.conf`
- ✅ Executes full outward MASQUERADE NAT on the active network interface
- ✅ Integrates `iptables-persistent` to prevent routing rule wipes during system updates or reboots

---

## 🌐 **3x-ui Panel Configuration Reference**

Once the panel installation is finished on your **Iran Server**, you need to mark your proxy outbounds to go through the GRE tunnel:

1. Access your **3x-ui Web Panel**
2. Navigate to **Panel Settings** ➡️ **Xray Configuration** ➡️ **Outbounds**
3. Replace your default `freedom` outbound block (tagged as `direct`) with this structure:

```json
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
```

---

## 🔍 **Troubleshooting & Verification**

If you experience connectivity issues, check the tunnel layer by running these diagnostic commands:

### 1. **Test Internal Tunnel Ping**
From the Iran Server, attempt to ping the Foreign Server's internal tunnel interface endpoint:

```bash
ping -c 4 10.10.10.2
```
> ℹ️ *Adjust the IP if you modified the default subnet during initialization.*

### 2. **Verify Tunnel Interface Status**
Ensure the interface exists and has the correct MTU (1360) bound to it:

```bash
ip a show gre1
```

### 3. **Check Policy Routing Rules**
Ensure the fwmark rule is actively pointing towards your routing tables:

```bash
ip rule show
ip route show table 100
```

---

## 📋 **System Requirements**

| Component | Requirement |
|-----------|-------------|
| **OS** | Ubuntu 18.04+ / Debian 9+ |
| **Architecture** | x86_64 / AMD64 |
| **Root Access** | Required |
| **Network** | Public IP on both servers |
| **Ports** | GRE protocol (IP protocol 47) must be allowed |

---

## ⚠️ **Important Notes**

- 🔒 **Security**: Ensure your firewall allows GRE protocol (IP protocol 47) between both servers
- 🔄 **Persistence**: All configurations survive system reboots
- 📦 **Dependencies**: Script automatically installs required packages (`iptables-persistent`, `gre`, etc.)
- 🛡️ **Backups**: Original configuration files are backed up before modifications

---

## 🤝 **Support & Contributions**

For issues, suggestions, or contributions:
- 📧 Open an issue on [GitHub](https://github.com/AmirAbbas-de/gre-tunnel/issues)
- 🔧 Fork the repository and submit a pull request
- ⭐ Star the project if you find it useful!

---

## 📜 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for the community**
