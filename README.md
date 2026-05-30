# VPN Server Auto-Installer

Auto-install script for a full-featured VPN server on **Ubuntu 18 / 20 / 22 / 24**.  
Installs, configures, and starts all services in a single command — no manual setup required.

---

## ⚡ One-Line Install

Run as **root** on your VPS:

```bash
apt-get update -y && apt-get install -y git && git clone https://github.com/Phechr-2025/vpnserver.git /etc/vpnserver-src && chmod +x /etc/vpnserver-src/install.sh && bash /etc/vpnserver-src/install.sh
```

> **Tip:** Make sure you are already logged in as `root` before running. If not, run `sudo su -` first.

---

## 📡 Services & Ports

| Service | Port(s) | Status |
|---|---|---|
| **SlowDNS** | All SSH Ports (DNS Tunnel) | ON |
| **OpenSSH** | 22, 2253 | ON |
| **Dropbear** | 443, 109, 143, 1153 | ON |
| **Stunnel5** | 443, 445, 777 | ON |
| **OpenVPN TCP** | 1194 | ON |
| **OpenVPN UDP** | 2200 | ON |
| **OpenVPN SSL** | 990 | OFF |
| **WebSocket SSH TLS** | 443 | ON |
| **WebSocket SSH HTTP** | 8880 | ON |
| **WebSocket OpenVPN** | 2086 | OFF |
| **Squid Proxy** | 3128, 8000 | OFF |
| **BadVPN UDP-GW** | 7100, 7200, 7300 | ON |
| **Nginx** | 89 | ON |
| **WireGuard** | 7070 | ON |
| **L2TP/IPSec** | 1701 | ON |
| **PPTP VPN** | 1732 | ON |
| **SSTP VPN** | 444 | ON |
| **Shadowsocks-R** | 1443–1543 | ON |
| **SS-OBFS TLS** | 2443–2543 | ON |
| **SS-OBFS HTTP** | 3443–3543 | ON |
| **OHP SSH** | 8181 | ON |
| **OHP Dropbear** | 8282 | ON |
| **OHP OpenVPN** | 8383 | OFF |
| **Trojan-Go** | 2087 | ON |
| **CloudFront WebSocket** | — | OFF |

---

## 🛡 Security & System Features

| Feature | Status |
|---|---|
| Timezone | Asia/Kuala_Lumpur (GMT+8) |
| Fail2Ban | ON |
| Dflate (SSH Compression) | ON |
| IPTables NAT | ON |
| Auto-Reboot | ON — daily at **05:00 GMT+8** |
| IPv6 | OFF |
| Auto-Delete Expired Accounts | ON — runs every 30 minutes |
| BBR TCP Congestion Control | ON |
| IP Forwarding | ON |

---

## 📁 File Structure

```
vpnserver/
├── install.sh          # Main installer — run this
├── menu/
│   └── menu.sh         # Management panel (type 'menu' after install)
└── README.md
```

---

## 🖥 Management Menu

After installation, type `menu` to open the management panel:

```
  MAIN MENU
  ─────────────────────────────
  [1] Service Status
  [2] Add User
  [3] Delete User
  [4] List Users
  [5] Service Control (Restart)
  [6] Show Credentials
  [7] System Information
  [0] Exit
```

---

## 📋 Requirements

- Ubuntu **18.04 / 20.04 / 22.04 / 24.04**
- Logged in as **root**
- Minimum **1 vCPU, 1 GB RAM** (2 GB recommended)
- Fresh VPS recommended for cleanest install

---

## 🔐 Credentials

After install, all generated passwords and keys are saved in:

```
/etc/vpnserver/
├── l2tp_psk.txt
├── pptp_creds.txt
├── shadowsocks_creds.txt
└── trojan_creds.txt
```

WireGuard keys are in `/etc/wireguard/`.

---

## 📝 Logs

- Install log: `/var/log/vpnserver-install.log`
- Expired account log: `/var/log/vpnserver-expired.log`
- OpenVPN log: `/var/log/openvpn-tcp.log`, `/var/log/openvpn-udp.log`

---

## ⚠️ Notes

- After install, the server will auto-reboot daily at **05:00 GMT+8**.
- Expired SSH accounts are checked and removed every **30 minutes**.
- OpenVPN, Squid, WebSocket-OpenVPN, OHP-OpenVPN, and CloudFront are installed but marked **OFF** by default. Start them manually via the menu if needed.
- On first login after install, the management menu opens automatically.

---

## 📜 License

MIT License — free to use, modify, and redistribute.
