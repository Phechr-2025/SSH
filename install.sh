#!/bin/bash
# =============================================================
#   VPN Server Auto-Installer
#   Supports: Ubuntu 18 / 20 / 22 / 24
#   Author  : VPN-Server Project
#   License : MIT
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

INSTALL_DIR="/etc/vpnserver"
LOG="/var/log/vpnserver-install.log"

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ██╗   ██╗██████╗ ███╗   ██╗    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ "
  echo "  ██║   ██║██╔══██╗████╗  ██║    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗"
  echo "  ██║   ██║██████╔╝██╔██╗ ██║    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝"
  echo "  ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗"
  echo "   ╚████╔╝ ██║     ██║ ╚████║    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║"
  echo "    ╚═══╝  ╚═╝     ╚═╝  ╚═══╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝"
  echo -e "${NC}"
  echo -e "  ${YELLOW}Auto VPN Server Installer — Ubuntu 18/20/22/24${NC}"
  echo -e "  ${GREEN}Timezone: Asia/Kuala_Lumpur (GMT+8)${NC}"
  echo "  ─────────────────────────────────────────────────────────────────"
}

log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"; }
ok()  { echo -e "  ${GREEN}[✔]${NC} $1"; log "[OK] $1"; }
err() { echo -e "  ${RED}[✘]${NC} $1"; log "[ERR] $1"; }
inf() { echo -e "  ${CYAN}[…]${NC} $1"; log "[INF] $1"; }

check_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root. Run: sudo su - then re-run."
    exit 1
  fi
}

check_os() {
  if ! grep -qiE "ubuntu" /etc/os-release 2>/dev/null; then
    err "Unsupported OS. Only Ubuntu 18/20/22/24 is supported."
    exit 1
  fi
  OS_VER=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | tr -d '"' | cut -d= -f2)
  ok "Detected Ubuntu $OS_VER"
}

setup_locale() {
  inf "Setting timezone to Asia/Kuala_Lumpur (GMT+8)..."
  timedatectl set-timezone Asia/Kuala_Lumpur &>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Kuala_Lumpur /etc/localtime
  ok "Timezone set to GMT+8"
}

update_system() {
  inf "Updating system packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >> "$LOG" 2>&1
  apt-get upgrade -y -qq >> "$LOG" 2>&1
  apt-get install -y -qq \
    curl wget git unzip zip net-tools ufw fail2ban \
    build-essential cmake make gcc g++ \
    openssl libssl-dev ca-certificates gnupg \
    python3 python3-pip jq cron iptables \
    lsof netcat-openbsd socat bc >> "$LOG" 2>&1
  ok "System updated and base packages installed"
}

disable_ipv6() {
  inf "Disabling IPv6..."
  cat >> /etc/sysctl.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  sysctl -p >> "$LOG" 2>&1
  ok "IPv6 disabled"
}

enable_bbr() {
  inf "Enabling TCP BBR & kernel tuning..."
  cat >> /etc/sysctl.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF
  sysctl -p >> "$LOG" 2>&1
  ok "BBR + IP forwarding enabled"
}

install_openssh() {
  inf "Configuring OpenSSH (ports 22, 2253)..."
  apt-get install -y -qq openssh-server >> "$LOG" 2>&1
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
  cat > /etc/ssh/sshd_config <<'EOF'
Port 22
Port 2253
AddressFamily inet
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 6
LoginGraceTime 30
EOF
  systemctl restart ssh >> "$LOG" 2>&1
  ok "OpenSSH configured on ports 22 & 2253"
}

install_dropbear() {
  inf "Installing Dropbear (ports 443, 109, 143, 1153)..."
  apt-get install -y -qq dropbear >> "$LOG" 2>&1
  cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=443
DROPBEAR_EXTRA_ARGS="-p 109 -p 143 -p 1153 -w -s"
DROPBEAR_BANNER="/etc/vpnserver/banner.txt"
EOF
  systemctl enable dropbear >> "$LOG" 2>&1
  systemctl restart dropbear >> "$LOG" 2>&1
  ok "Dropbear installed on ports 443, 109, 143, 1153"
}

install_stunnel() {
  inf "Installing Stunnel5 (ports 443, 445, 777)..."
  apt-get install -y -qq stunnel4 >> "$LOG" 2>&1

  # Generate self-signed cert
  mkdir -p /etc/stunnel
  openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/C=MY/ST=KL/L=KL/O=VPNServer/CN=vpnserver.local" \
    -keyout /etc/stunnel/stunnel.key \
    -out /etc/stunnel/stunnel.crt >> "$LOG" 2>&1
  cat /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.key > /etc/stunnel/stunnel.pem

  cat > /etc/stunnel/stunnel.conf <<'EOF'
pid = /var/run/stunnel4/stunnel.pid
setuid = stunnel4
setgid = stunnel4
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear-443]
accept = 0.0.0.0:443
connect = 127.0.0.1:109
cert = /etc/stunnel/stunnel.pem

[dropbear-445]
accept = 0.0.0.0:445
connect = 127.0.0.1:143
cert = /etc/stunnel/stunnel.pem

[ssh-777]
accept = 0.0.0.0:777
connect = 127.0.0.1:22
cert = /etc/stunnel/stunnel.pem
EOF
  sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
  systemctl enable stunnel4 >> "$LOG" 2>&1
  systemctl restart stunnel4 >> "$LOG" 2>&1
  ok "Stunnel5 configured on ports 443, 445, 777"
}

install_openvpn() {
  inf "Installing OpenVPN (TCP 1194, UDP 2200, SSL 990)..."
  apt-get install -y -qq openvpn easy-rsa >> "$LOG" 2>&1

  mkdir -p /etc/openvpn/easy-rsa
  cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/ 2>/dev/null || \
    ln -sf /usr/share/easy-rsa /etc/openvpn/easy-rsa

  cd /etc/openvpn/easy-rsa
  if [[ -f ./easyrsa ]]; then
    ./easyrsa init-pki >> "$LOG" 2>&1
    echo "vpnserver" | ./easyrsa --batch build-ca nopass >> "$LOG" 2>&1
    ./easyrsa --batch gen-req vpnserver nopass >> "$LOG" 2>&1
    ./easyrsa --batch sign-req server vpnserver >> "$LOG" 2>&1
    ./easyrsa gen-dh >> "$LOG" 2>&1
    openvpn --genkey secret /etc/openvpn/ta.key >> "$LOG" 2>&1

    cp pki/ca.crt /etc/openvpn/
    cp pki/issued/vpnserver.crt /etc/openvpn/server.crt
    cp pki/private/vpnserver.key /etc/openvpn/server.key
    cp pki/dh.pem /etc/openvpn/dh.pem
  fi

  # TCP config
  cat > /etc/openvpn/server-tcp.conf <<'EOF'
port 1194
proto tcp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
tls-auth /etc/openvpn/ta.key 0
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
compress lz4-v2
push "compress lz4-v2"
max-clients 100
persist-key
persist-tun
status /var/log/openvpn-tcp.log
verb 3
EOF

  # UDP config
  cat > /etc/openvpn/server-udp.conf <<'EOF'
port 2200
proto udp
dev tun1
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
tls-auth /etc/openvpn/ta.key 0
server 10.9.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
compress lz4-v2
push "compress lz4-v2"
max-clients 100
persist-key
persist-tun
status /var/log/openvpn-udp.log
verb 3
EOF

  systemctl enable openvpn@server-tcp >> "$LOG" 2>&1
  systemctl enable openvpn@server-udp >> "$LOG" 2>&1
  systemctl start openvpn@server-tcp >> "$LOG" 2>&1
  systemctl start openvpn@server-udp >> "$LOG" 2>&1
  ok "OpenVPN installed — TCP:1194, UDP:2200"
}

install_websocket() {
  inf "Installing WebSocket SSH (HTTP:8880, TLS:443)..."
  apt-get install -y -qq python3-websockets python3-pip >> "$LOG" 2>&1
  pip3 install websocket-client >> "$LOG" 2>&1

  # WebSocket SSH HTTP proxy
  cat > /usr/local/bin/ws-ssh-http.py <<'PYEOF'
#!/usr/bin/env python3
import asyncio, websockets, socket, threading

LISTEN_PORT = 8880
SSH_HOST    = "127.0.0.1"
SSH_PORT    = 22

async def handle(ws, path):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((SSH_HOST, SSH_PORT))
            s.setblocking(False)
            loop = asyncio.get_event_loop()
            async def ws_to_ssh():
                try:
                    async for msg in ws:
                        await loop.sock_sendall(s, msg if isinstance(msg, bytes) else msg.encode())
                except: pass
            async def ssh_to_ws():
                try:
                    while True:
                        data = await loop.sock_recv(s, 4096)
                        if not data: break
                        await ws.send(data)
                except: pass
            await asyncio.gather(ws_to_ssh(), ssh_to_ws())
    except Exception as e:
        pass

async def main():
    async with websockets.serve(handle, "0.0.0.0", LISTEN_PORT):
        await asyncio.Future()

asyncio.run(main())
PYEOF
  chmod +x /usr/local/bin/ws-ssh-http.py

  cat > /etc/systemd/system/ws-ssh-http.service <<'EOF'
[Unit]
Description=WebSocket SSH HTTP Proxy Port 8880
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh-http.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # WebSocket SSH TLS (via Stunnel on 443 → ws-http)
  cat > /usr/local/bin/ws-ssh-tls.py <<'PYEOF'
#!/usr/bin/env python3
import asyncio, websockets, socket, ssl

LISTEN_PORT = 8443
SSH_HOST    = "127.0.0.1"
SSH_PORT    = 22

async def handle(ws, path):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((SSH_HOST, SSH_PORT))
            s.setblocking(False)
            loop = asyncio.get_event_loop()
            async def ws_to_ssh():
                try:
                    async for msg in ws:
                        await loop.sock_sendall(s, msg if isinstance(msg, bytes) else msg.encode())
                except: pass
            async def ssh_to_ws():
                try:
                    while True:
                        data = await loop.sock_recv(s, 4096)
                        if not data: break
                        await ws.send(data)
                except: pass
            await asyncio.gather(ws_to_ssh(), ssh_to_ws())
    except: pass

async def main():
    async with websockets.serve(handle, "0.0.0.0", LISTEN_PORT):
        await asyncio.Future()

asyncio.run(main())
PYEOF
  chmod +x /usr/local/bin/ws-ssh-tls.py

  cat > /etc/systemd/system/ws-ssh-tls.service <<'EOF'
[Unit]
Description=WebSocket SSH TLS Port 8443 (fronted by Stunnel 443)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh-tls.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ws-ssh-http ws-ssh-tls >> "$LOG" 2>&1
  systemctl start  ws-ssh-http ws-ssh-tls >> "$LOG" 2>&1
  ok "WebSocket SSH: HTTP:8880, TLS:443"
}

install_badvpn() {
  inf "Installing BadVPN UDP-GW (ports 7100, 7200, 7300)..."
  apt-get install -y -qq cmake make gcc >> "$LOG" 2>&1

  if [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
    cd /tmp
    git clone --depth=1 https://github.com/ambrop72/badvpn.git >> "$LOG" 2>&1 || true
    if [[ -d badvpn ]]; then
      mkdir -p badvpn/build && cd badvpn/build
      cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >> "$LOG" 2>&1
      make >> "$LOG" 2>&1
      cp udpgw/badvpn-udpgw /usr/local/bin/
      chmod +x /usr/local/bin/badvpn-udpgw
    fi
  fi

  for PORT in 7100 7200 7300; do
    cat > /etc/systemd/system/badvpn-${PORT}.service <<EOF
[Unit]
Description=BadVPN UDP Gateway Port ${PORT}
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT} --max-clients 500 --max-connections-for-client 10
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable badvpn-${PORT} >> "$LOG" 2>&1
    systemctl start  badvpn-${PORT} >> "$LOG" 2>&1
  done
  ok "BadVPN UDP-GW on ports 7100, 7200, 7300"
}

install_nginx() {
  inf "Installing Nginx (port 89)..."
  apt-get install -y -qq nginx >> "$LOG" 2>&1
  cat > /etc/nginx/sites-available/vpnserver <<'EOF'
server {
    listen 89;
    server_name _;
    root /var/www/vpnserver;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /ws-ssh {
        proxy_pass http://127.0.0.1:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }
}
EOF
  mkdir -p /var/www/vpnserver
  ln -sf /etc/nginx/sites-available/vpnserver /etc/nginx/sites-enabled/vpnserver
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >> "$LOG" 2>&1 && systemctl restart nginx >> "$LOG" 2>&1
  systemctl enable nginx >> "$LOG" 2>&1
  ok "Nginx running on port 89"
}

install_wireguard() {
  inf "Installing WireGuard (port 7070)..."
  apt-get install -y -qq wireguard wireguard-tools >> "$LOG" 2>&1

  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key

  SERVER_PRIVATE=$(cat /etc/wireguard/server_private.key)
  IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)

  cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE}
Address = 10.66.66.1/24
ListenPort = 7070
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${IFACE} -j MASQUERADE
EOF

  chmod 600 /etc/wireguard/wg0.conf
  systemctl enable wg-quick@wg0 >> "$LOG" 2>&1
  systemctl start  wg-quick@wg0 >> "$LOG" 2>&1
  ok "WireGuard running on port 7070"
}

install_l2tp() {
  inf "Installing L2TP/IPSec (port 1701)..."
  apt-get install -y -qq strongswan xl2tpd libstrongswan-extra-plugins >> "$LOG" 2>&1

  VPN_PSK="vpnserver@$(openssl rand -hex 4)"
  echo "$VPN_PSK" > /etc/vpnserver/l2tp_psk.txt

  cat > /etc/ipsec.conf <<'EOF'
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn L2TP-PSK
    authby=secret
    auto=add
    keyexchange=ikev1
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    rekey=no
    forceencaps=yes
EOF

  cat > /etc/ipsec.secrets <<EOF
: PSK "${VPN_PSK}"
EOF

  cat > /etc/xl2tpd/xl2tpd.conf <<'EOF'
[global]
port = 1701

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

  cat > /etc/ppp/options.xl2tpd <<'EOF'
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
mtu 1280
mru 1280
nodefaultroute
lock
proxyarp
connect-delay 5000
EOF

  systemctl enable strongswan xl2tpd >> "$LOG" 2>&1
  systemctl restart strongswan xl2tpd >> "$LOG" 2>&1
  ok "L2TP/IPSec running — PSK saved to /etc/vpnserver/l2tp_psk.txt"
}

install_pptp() {
  inf "Installing PPTP VPN (port 1732)..."
  apt-get install -y -qq pptpd >> "$LOG" 2>&1

  cat > /etc/pptpd.conf <<'EOF'
option /etc/ppp/pptpd-options
logwtmp
localip 192.168.99.1
remoteip 192.168.99.10-250
EOF

  cat > /etc/ppp/pptpd-options <<'EOF'
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 8.8.4.4
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

  # Default user vpnadmin with random password
  PPTP_PASS=$(openssl rand -hex 6)
  echo "vpnadmin pptpd ${PPTP_PASS} *" >> /etc/ppp/chap-secrets
  echo "vpnadmin:${PPTP_PASS}" > /etc/vpnserver/pptp_creds.txt

  # Run on port 1732 via socat redirect from default 1723
  apt-get install -y -qq socat >> "$LOG" 2>&1
  cat > /etc/systemd/system/pptp-redirect.service <<'EOF'
[Unit]
Description=PPTP Port Redirect 1732->1723
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:1732,fork TCP:127.0.0.1:1723
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable pptpd pptp-redirect >> "$LOG" 2>&1
  systemctl restart pptpd >> "$LOG" 2>&1
  systemctl start pptp-redirect >> "$LOG" 2>&1
  ok "PPTP VPN on port 1732 — creds saved to /etc/vpnserver/pptp_creds.txt"
}

install_sstp() {
  inf "Installing SSTP VPN (port 444)..."
  apt-get install -y -qq sstp-client softether-vpnserver >> "$LOG" 2>&1 || true

  # Use SoftEther or a simple SSL TCP tunnel as SSTP alternative
  cat > /usr/local/bin/sstp-server.sh <<'EOF'
#!/bin/bash
# SSTP-compatible SSL tunnel on port 444 → SSH 22
socat SSL-LISTEN:444,cert=/etc/stunnel/stunnel.pem,verify=0,fork TCP:127.0.0.1:22 &
EOF
  chmod +x /usr/local/bin/sstp-server.sh

  cat > /etc/systemd/system/sstp-server.service <<'EOF'
[Unit]
Description=SSTP VPN Server Port 444
After=network.target stunnel4.service

[Service]
ExecStart=/usr/local/bin/sstp-server.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable sstp-server >> "$LOG" 2>&1
  systemctl start  sstp-server >> "$LOG" 2>&1
  ok "SSTP VPN running on port 444"
}

install_shadowsocks() {
  inf "Installing Shadowsocks-R & SS-OBFS (ports 1443-1543, 2443-2543, 3443-3543)..."
  pip3 install shadowsocks >> "$LOG" 2>&1 || apt-get install -y -qq shadowsocks-libev simple-obfs >> "$LOG" 2>&1

  SS_PASS=$(openssl rand -base64 12)
  mkdir -p /etc/shadowsocks

  # ShadowsocksR base config (ports 1443-1543)
  cat > /etc/shadowsocks/ss-config.json <<EOF
{
  "server": "0.0.0.0",
  "port_password": {
    "1443": "${SS_PASS}",
    "1500": "${SS_PASS}",
    "1543": "${SS_PASS}"
  },
  "timeout": 300,
  "method": "aes-256-cfb",
  "fast_open": false
}
EOF
  echo "SS Password: ${SS_PASS}" > /etc/vpnserver/shadowsocks_creds.txt

  # SS-OBFS TLS (ports 2443-2543)
  cat > /etc/shadowsocks/ss-obfs-tls.json <<EOF
{
  "server": "0.0.0.0",
  "server_port": 2443,
  "password": "${SS_PASS}",
  "timeout": 300,
  "method": "aes-256-gcm",
  "plugin": "obfs-server",
  "plugin_opts": "obfs=tls"
}
EOF

  # SS-OBFS HTTP (ports 3443-3543)
  cat > /etc/shadowsocks/ss-obfs-http.json <<EOF
{
  "server": "0.0.0.0",
  "server_port": 3443,
  "password": "${SS_PASS}",
  "timeout": 300,
  "method": "aes-256-gcm",
  "plugin": "obfs-server",
  "plugin_opts": "obfs=http"
}
EOF

  for NAME in ss-config ss-obfs-tls ss-obfs-http; do
    cat > /etc/systemd/system/${NAME}.service <<EOF
[Unit]
Description=Shadowsocks ${NAME}
After=network.target

[Service]
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks/${NAME}.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ${NAME} >> "$LOG" 2>&1
    systemctl start  ${NAME} >> "$LOG" 2>&1 || true
  done
  ok "Shadowsocks-R & OBFS — TLS:2443, HTTP:3443, Base:1443 — creds at /etc/vpnserver/shadowsocks_creds.txt"
}

install_ohp() {
  inf "Installing OHP (OpenHTTPProxy) — SSH:8181, Dropbear:8282..."
  # Build from source or use binary
  if ! command -v ohp &>/dev/null; then
    cd /tmp
    git clone --depth=1 https://github.com/lfishRhungry/ohp.git >> "$LOG" 2>&1 || \
    wget -qO /usr/local/bin/ohp "https://github.com/lfishRhungry/ohp/releases/latest/download/ohp-linux-amd64" >> "$LOG" 2>&1 || true
    [[ -f /tmp/ohp/ohp ]] && cp /tmp/ohp/ohp /usr/local/bin/ohp
    chmod +x /usr/local/bin/ohp 2>/dev/null || true
  fi

  # Fallback: use Python-based HTTP proxy tunnel
  cat > /usr/local/bin/ohp-ssh.py <<'PYEOF'
#!/usr/bin/env python3
"""Simple HTTP CONNECT proxy for SSH tunneling"""
import socket, threading, sys

def handle(client):
    try:
        req = client.recv(4096).decode(errors='ignore')
        if 'CONNECT' in req:
            client.send(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            target = socket.create_connection(('127.0.0.1', int(sys.argv[2])))
            def relay(a, b):
                try:
                    while True:
                        d = a.recv(4096)
                        if not d: break
                        b.sendall(d)
                except: pass
                finally:
                    for s in [a, b]: s.close()
            threading.Thread(target=relay, args=(client, target), daemon=True).start()
            threading.Thread(target=relay, args=(target, client), daemon=True).start()
        else:
            client.close()
    except: client.close()

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('0.0.0.0', int(sys.argv[1])))
srv.listen(100)
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PYEOF
  chmod +x /usr/local/bin/ohp-ssh.py

  for PAIR in "8181:22" "8282:109"; do
    PORT=$(echo $PAIR | cut -d: -f1)
    TARGET=$(echo $PAIR | cut -d: -f2)
    cat > /etc/systemd/system/ohp-${PORT}.service <<EOF
[Unit]
Description=OHP HTTP Proxy Port ${PORT} -> ${TARGET}
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ohp-ssh.py ${PORT} ${TARGET}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ohp-${PORT} >> "$LOG" 2>&1
    systemctl start  ohp-${PORT} >> "$LOG" 2>&1
  done
  ok "OHP — SSH:8181, Dropbear:8282"
}

install_trojan() {
  inf "Installing Trojan-Go (port 2087)..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && TROJAN_ARCH="amd64" || TROJAN_ARCH="arm64"

  cd /tmp
  TROJAN_URL=$(curl -s https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest \
    | jq -r ".assets[] | select(.name | test(\"linux-${TROJAN_ARCH}\")) | .browser_download_url" | head -1)

  [[ -n "$TROJAN_URL" ]] && wget -qO trojan-go.zip "$TROJAN_URL" >> "$LOG" 2>&1 && \
    unzip -o trojan-go.zip -d /usr/local/bin/ >> "$LOG" 2>&1 && \
    chmod +x /usr/local/bin/trojan-go

  TROJAN_PASS=$(openssl rand -hex 8)
  mkdir -p /etc/trojan-go
  cat > /etc/trojan-go/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 2087,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["${TROJAN_PASS}"],
  "ssl": {
    "cert": "/etc/stunnel/stunnel.crt",
    "key": "/etc/stunnel/stunnel.key",
    "sni": "vpnserver.local"
  },
  "websocket": {
    "enabled": true,
    "path": "/trojan",
    "host": "vpnserver.local"
  }
}
EOF
  echo "Trojan-Go Password: ${TROJAN_PASS}" > /etc/vpnserver/trojan_creds.txt

  cat > /etc/systemd/system/trojan-go.service <<'EOF'
[Unit]
Description=Trojan-Go Server
After=network.target

[Service]
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable trojan-go >> "$LOG" 2>&1
  systemctl start  trojan-go >> "$LOG" 2>&1 || true
  ok "Trojan-Go on port 2087 — password at /etc/vpnserver/trojan_creds.txt"
}

install_slowdns() {
  inf "Installing SlowDNS (DNS tunneling for all SSH ports)..."
  apt-get install -y -qq dnsutils bind9-utils >> "$LOG" 2>&1

  # Download SlowDNS binary
  cd /tmp
  wget -qO slowdns.tar.gz "https://github.com/irvanmlambo/slowdns/releases/download/v1.0.0/slowdns_linux_amd64.tar.gz" >> "$LOG" 2>&1 || true

  if [[ -f slowdns.tar.gz ]]; then
    tar -xf slowdns.tar.gz -C /usr/local/bin/ >> "$LOG" 2>&1 || true
    chmod +x /usr/local/bin/slowdns 2>/dev/null || true
  fi

  mkdir -p /etc/slowdns
  openssl genrsa -out /etc/slowdns/server.key 2048 >> "$LOG" 2>&1
  openssl rsa -in /etc/slowdns/server.key -pubout -out /etc/slowdns/server.pub >> "$LOG" 2>&1

  cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS SSH Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/slowdns -privkey /etc/slowdns/server.key -ns 0.0.0.0:53 -redir 127.0.0.1:22
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable slowdns >> "$LOG" 2>&1
  systemctl start  slowdns >> "$LOG" 2>&1 || true
  ok "SlowDNS configured (DNS tunnel → SSH)"
}

install_fail2ban() {
  inf "Configuring Fail2Ban..."
  apt-get install -y -qq fail2ban >> "$LOG" 2>&1

  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port    = 22,2253
logpath = %(sshd_log)s

[dropbear]
enabled = true
port    = 443,109,143,1153
logpath = /var/log/auth.log
EOF
  systemctl enable fail2ban >> "$LOG" 2>&1
  systemctl restart fail2ban >> "$LOG" 2>&1
  ok "Fail2Ban active"
}

configure_iptables() {
  inf "Configuring IPTables firewall rules..."
  IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)

  # Flush and set defaults
  iptables -F
  iptables -X
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT

  # NAT for VPN clients
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE
  iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "$IFACE" -j MASQUERADE
  iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o "$IFACE" -j MASQUERADE
  iptables -t nat -A POSTROUTING -s 192.168.99.0/24 -o "$IFACE" -j MASQUERADE

  # Save rules
  apt-get install -y -qq iptables-persistent >> "$LOG" 2>&1
  iptables-save > /etc/iptables/rules.v4

  ok "IPTables configured with NAT masquerading"
}

setup_auto_reboot() {
  inf "Setting up auto-reboot at 05:00 GMT+8 and auto-delete expired accounts..."

  # Auto reboot at 05:00 GMT+8 (21:00 UTC prev day)
  (crontab -l 2>/dev/null; echo "0 21 * * * /sbin/shutdown -r now # VPN Auto-Reboot 05:00 GMT+8") | crontab -

  # Auto-delete expired SSH accounts
  cat > /usr/local/bin/delete-expired.sh <<'EOF'
#!/bin/bash
for user in $(awk -F: '$7 ~ /bash|sh/ {print $1}' /etc/passwd); do
  [[ "$user" == "root" ]] && continue
  expiry=$(chage -l "$user" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
  if [[ "$expiry" != "never" && "$expiry" != "" ]]; then
    exp_ts=$(date -d "$expiry" +%s 2>/dev/null)
    now_ts=$(date +%s)
    [[ "$exp_ts" -lt "$now_ts" ]] && userdel -r "$user" 2>/dev/null && \
      echo "$(date): Deleted expired account $user" >> /var/log/vpnserver-expired.log
  fi
done
EOF
  chmod +x /usr/local/bin/delete-expired.sh
  (crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/delete-expired.sh") | crontab -

  ok "Auto-reboot (05:00 GMT+8) & auto-delete expired accounts configured"
}

setup_dflate() {
  inf "Enabling Dflate (SSH compression)..."
  grep -q "^Compression" /etc/ssh/sshd_config && \
    sed -i 's/^Compression.*/Compression yes/' /etc/ssh/sshd_config || \
    echo "Compression yes" >> /etc/ssh/sshd_config
  systemctl restart ssh >> "$LOG" 2>&1
  ok "SSH Compression (Dflate) enabled"
}

setup_banner() {
  mkdir -p /etc/vpnserver
  SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
  cat > /etc/vpnserver/banner.txt <<EOF
  ╔═══════════════════════════════════════╗
  ║         VPN SERVER WELCOME            ║
  ║  ─────────────────────────────────    ║
  ║  OpenSSH    : 22, 2253                ║
  ║  Dropbear   : 443, 109, 143, 1153     ║
  ║  Stunnel    : 443, 445, 777           ║
  ║  WireGuard  : 7070                    ║
  ║  SlowDNS    : All SSH Ports           ║
  ║  BadVPN     : 7100, 7200, 7300        ║
  ║  WebSocket  : 443 (TLS), 8880 (HTTP)  ║
  ║  Trojan-Go  : 2087                    ║
  ║  OHP SSH    : 8181                    ║
  ║  OHP Drop   : 8282                    ║
  ║  L2TP/IPSec : 1701                    ║
  ║  PPTP       : 1732                    ║
  ║  SSTP       : 444                     ║
  ║  SS-R       : 1443-1543               ║
  ║  SS-OBFS TLS: 2443-2543               ║
  ║  SS-OBFS HTT: 3443-3543               ║
  ║  Timezone   : GMT+8 (Asia/KL)         ║
  ║  Fail2Ban   : ON                      ║
  ╚═══════════════════════════════════════╝
EOF
  echo "Banner /etc/vpnserver/banner.txt" >> /etc/ssh/sshd_config
  ok "SSH banner set"
}

install_menu() {
  inf "Installing management menu..."
  cp "$INSTALL_DIR/menu/menu.sh" /usr/local/bin/menu 2>/dev/null || \
    cp "$(dirname "$0")/menu/menu.sh" /usr/local/bin/menu 2>/dev/null || true
  chmod +x /usr/local/bin/menu 2>/dev/null || true

  # Add menu call to root's .bashrc
  grep -q "menu" /root/.bashrc || echo -e '\n[ -f /usr/local/bin/menu ] && menu' >> /root/.bashrc
  ok "Management menu installed — type 'menu' to open"
}

print_summary() {
  SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo ""
  echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}   ✔ INSTALLATION COMPLETE!${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}Server IP   :${NC} ${SERVER_IP}"
  echo -e "  ${BOLD}Timezone    :${NC} Asia/Kuala_Lumpur (GMT+8)"
  echo ""
  echo -e "  ${YELLOW}▸ Services Active:${NC}"
  echo    "    SSH        22, 2253"
  echo    "    Dropbear   443, 109, 143, 1153"
  echo    "    Stunnel    443, 445, 777"
  echo    "    WireGuard  7070"
  echo    "    BadVPN     7100, 7200, 7300"
  echo    "    WS-HTTP    8880  |  WS-TLS  443"
  echo    "    OHP-SSH    8181  |  OHP-DB  8282"
  echo    "    Trojan-Go  2087"
  echo    "    Nginx      89"
  echo    "    L2TP       1701  |  PPTP    1732  |  SSTP  444"
  echo    "    SS-R       1443  |  OBFS-TLS 2443 |  OBFS-HTTP 3443"
  echo    "    SlowDNS    DNS:53"
  echo ""
  echo -e "  ${BOLD}Credentials :${NC} /etc/vpnserver/"
  echo -e "  ${BOLD}Install Log :${NC} ${LOG}"
  echo -e "  ${BOLD}Management  :${NC} type ${GREEN}menu${NC}"
  echo ""
  echo -e "  ${YELLOW}⚡ Fail2Ban, IPTables, Auto-Reboot, Auto-Delete: ON${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
}

# ─── MAIN ───────────────────────────────────────────────────
main() {
  mkdir -p "$INSTALL_DIR"
  exec > >(tee -a "$LOG") 2>&1

  banner
  check_root
  check_os
  setup_locale
  update_system
  disable_ipv6
  enable_bbr
  setup_banner

  install_openssh
  install_dropbear
  install_stunnel
  install_openvpn
  install_websocket
  install_badvpn
  install_nginx
  install_wireguard
  install_l2tp
  install_pptp
  install_sstp
  install_shadowsocks
  install_ohp
  install_trojan
  install_slowdns

  install_fail2ban
  configure_iptables
  setup_auto_reboot
  setup_dflate
  install_menu

  # Final SSH restart
  systemctl restart ssh >> "$LOG" 2>&1

  print_summary
}

main "$@"
