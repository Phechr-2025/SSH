#!/bin/bash
# VPN Server Management Menu

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
BLINK='\033[5m'

SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
DATE_NOW=$(TZ='Asia/Kuala_Lumpur' date '+%A, %d %b %Y  %H:%M:%S GMT+8')

svc_status() {
  systemctl is-active "$1" &>/dev/null && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}"
}

show_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │              VPN SERVER MANAGEMENT PANEL                    │"
  echo "  ├─────────────────────────────────────────────────────────────┤"
  printf "  │  %-20s %-38s │\n" "Server IP:" "$SERVER_IP"
  printf "  │  %-20s %-38s │\n" "Date/Time:" "$DATE_NOW"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo -e "${NC}"
}

show_status() {
  show_header
  echo -e "  ${BOLD}${YELLOW}SERVICE STATUS${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  printf "  %-28s %s\n" "SSH (22, 2253):"         "$(svc_status ssh)"
  printf "  %-28s %s\n" "Dropbear (443,109,143):" "$(svc_status dropbear)"
  printf "  %-28s %s\n" "Stunnel (443,445,777):"  "$(svc_status stunnel4)"
  printf "  %-28s %s\n" "OpenVPN TCP (1194):"     "$(svc_status openvpn@server-tcp)"
  printf "  %-28s %s\n" "OpenVPN UDP (2200):"     "$(svc_status openvpn@server-udp)"
  printf "  %-28s %s\n" "WireGuard (7070):"       "$(svc_status wg-quick@wg0)"
  printf "  %-28s %s\n" "WS-HTTP (8880):"         "$(svc_status ws-ssh-http)"
  printf "  %-28s %s\n" "WS-TLS (443):"           "$(svc_status ws-ssh-tls)"
  printf "  %-28s %s\n" "BadVPN (7100,7200,7300):""$(svc_status badvpn-7100)"
  printf "  %-28s %s\n" "Nginx (89):"             "$(svc_status nginx)"
  printf "  %-28s %s\n" "L2TP/IPSec (1701):"      "$(svc_status xl2tpd)"
  printf "  %-28s %s\n" "PPTP (1732):"            "$(svc_status pptpd)"
  printf "  %-28s %s\n" "SSTP (444):"             "$(svc_status sstp-server)"
  printf "  %-28s %s\n" "Shadowsocks-R (1443):"   "$(svc_status ss-config)"
  printf "  %-28s %s\n" "SS-OBFS TLS (2443):"     "$(svc_status ss-obfs-tls)"
  printf "  %-28s %s\n" "SS-OBFS HTTP (3443):"    "$(svc_status ss-obfs-http)"
  printf "  %-28s %s\n" "OHP SSH (8181):"         "$(svc_status ohp-8181)"
  printf "  %-28s %s\n" "OHP Dropbear (8282):"    "$(svc_status ohp-8282)"
  printf "  %-28s %s\n" "Trojan-Go (2087):"       "$(svc_status trojan-go)"
  printf "  %-28s %s\n" "SlowDNS:"                "$(svc_status slowdns)"
  printf "  %-28s %s\n" "Fail2Ban:"               "$(svc_status fail2ban)"
  echo "  ───────────────────────────────────────────────────────────────"
  echo -e "\n  Press any key to return..."; read -n1
}

add_user_menu() {
  show_header
  echo -e "  ${BOLD}${YELLOW}ADD SSH/VPN USER${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  read -rp "  Username    : " USERNAME
  [[ -z "$USERNAME" ]] && echo -e "  ${RED}Username cannot be empty${NC}" && sleep 2 && return
  read -rsp "  Password    : " PASSWORD; echo
  [[ -z "$PASSWORD" ]] && echo -e "  ${RED}Password cannot be empty${NC}" && sleep 2 && return
  read -rp "  Expire Days : " DAYS
  [[ -z "$DAYS" ]] && DAYS=30

  if id "$USERNAME" &>/dev/null; then
    echo -e "  ${RED}User '$USERNAME' already exists${NC}"; sleep 2; return
  fi

  useradd -M -s /bin/false -e "$(date -d "+${DAYS} days" '+%Y-%m-%d')" "$USERNAME"
  echo "${USERNAME}:${PASSWORD}" | chpasswd

  EXP_DATE=$(chage -l "$USERNAME" | grep "Account expires" | awk -F: '{print $2}' | xargs)
  echo ""
  echo -e "  ${GREEN}✔ User Created Successfully!${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  printf "  %-18s %s\n" "Username:"   "$USERNAME"
  printf "  %-18s %s\n" "Password:"   "$PASSWORD"
  printf "  %-18s %s\n" "Expires:"    "$EXP_DATE"
  printf "  %-18s %s\n" "Server IP:"  "$SERVER_IP"
  echo "  ───────────────────────────────────────────────────────────────"
  echo -e "\n  Press any key to return..."; read -n1
}

del_user_menu() {
  show_header
  echo -e "  ${BOLD}${YELLOW}DELETE SSH/VPN USER${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  echo "  Current users:"
  awk -F: '$7 ~ /false/ && $3 >= 1000 {print "  - "$1}' /etc/passwd
  echo ""
  read -rp "  Username to delete: " USERNAME
  [[ -z "$USERNAME" ]] && return
  if id "$USERNAME" &>/dev/null; then
    userdel -r "$USERNAME" 2>/dev/null
    echo -e "  ${GREEN}✔ User '$USERNAME' deleted${NC}"
  else
    echo -e "  ${RED}User '$USERNAME' not found${NC}"
  fi
  sleep 2
}

list_users_menu() {
  show_header
  echo -e "  ${BOLD}${YELLOW}USER LIST${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  printf "  %-20s %-18s %-12s\n" "Username" "Expiry Date" "Status"
  echo "  ───────────────────────────────────────────────────────────────"
  while IFS=: read -r user _ uid _ _ _ shell; do
    [[ "$shell" != *false* && "$shell" != */nologin* ]] && continue
    [[ "$uid" -lt 1000 ]] && continue
    exp=$(chage -l "$user" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
    exp_ts=$(date -d "$exp" +%s 2>/dev/null)
    now_ts=$(date +%s)
    if [[ -z "$exp" || "$exp" == "never" ]]; then
      status="${GREEN}Active${NC}"
    elif [[ "$exp_ts" -lt "$now_ts" ]]; then
      status="${RED}Expired${NC}"
    else
      days_left=$(( (exp_ts - now_ts) / 86400 ))
      status="${YELLOW}${days_left}d left${NC}"
    fi
    printf "  %-20s %-18s " "$user" "$exp"
    echo -e "$status"
  done < /etc/passwd
  echo "  ───────────────────────────────────────────────────────────────"
  echo -e "\n  Press any key to return..."; read -n1
}

service_control_menu() {
  show_header
  echo -e "  ${BOLD}${YELLOW}SERVICE CONTROL${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  echo "  [1] Restart All Services"
  echo "  [2] Restart SSH"
  echo "  [3] Restart Dropbear"
  echo "  [4] Restart Stunnel"
  echo "  [5] Restart OpenVPN"
  echo "  [6] Restart WireGuard"
  echo "  [7] Restart Nginx"
  echo "  [8] Restart Fail2Ban"
  echo "  [9] Restart Shadowsocks"
  echo "  [0] Back"
  echo "  ───────────────────────────────────────────────────────────────"
  read -rp "  Choice: " C
  case $C in
    1) for s in ssh dropbear stunnel4 openvpn@server-tcp openvpn@server-udp \
                wg-quick@wg0 nginx fail2ban trojan-go ws-ssh-http ws-ssh-tls; do
         systemctl restart "$s" 2>/dev/null && echo -e "  ${GREEN}✔ $s restarted${NC}" || true
       done ;;
    2) systemctl restart ssh && echo -e "  ${GREEN}✔ SSH restarted${NC}" ;;
    3) systemctl restart dropbear && echo -e "  ${GREEN}✔ Dropbear restarted${NC}" ;;
    4) systemctl restart stunnel4 && echo -e "  ${GREEN}✔ Stunnel restarted${NC}" ;;
    5) systemctl restart openvpn@server-tcp openvpn@server-udp && echo -e "  ${GREEN}✔ OpenVPN restarted${NC}" ;;
    6) systemctl restart wg-quick@wg0 && echo -e "  ${GREEN}✔ WireGuard restarted${NC}" ;;
    7) systemctl restart nginx && echo -e "  ${GREEN}✔ Nginx restarted${NC}" ;;
    8) systemctl restart fail2ban && echo -e "  ${GREEN}✔ Fail2Ban restarted${NC}" ;;
    9) systemctl restart ss-config ss-obfs-tls ss-obfs-http 2>/dev/null && echo -e "  ${GREEN}✔ Shadowsocks restarted${NC}" ;;
    0) return ;;
  esac
  sleep 2
}

show_credentials() {
  show_header
  echo -e "  ${BOLD}${YELLOW}SAVED CREDENTIALS${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  for f in /etc/vpnserver/*.txt; do
    [[ -f "$f" ]] || continue
    echo -e "  ${CYAN}$(basename "$f"):${NC}"
    cat "$f" | sed 's/^/    /'
    echo ""
  done
  echo "  ───────────────────────────────────────────────────────────────"
  echo -e "\n  Press any key to return..."; read -n1
}

system_info_menu() {
  show_header
  echo -e "  ${BOLD}${YELLOW}SYSTEM INFORMATION${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  printf "  %-20s %s\n" "OS:" "$(lsb_release -ds 2>/dev/null)"
  printf "  %-20s %s\n" "Kernel:" "$(uname -r)"
  printf "  %-20s %s\n" "Uptime:" "$(uptime -p)"
  printf "  %-20s %s\n" "CPU Load:" "$(uptime | awk -F'load average:' '{print $2}')"
  printf "  %-20s %s\n" "RAM Usage:" "$(free -h | awk '/Mem/{print $3"/"$2}')"
  printf "  %-20s %s\n" "Disk Usage:" "$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
  printf "  %-20s %s\n" "Server IP:" "$SERVER_IP"
  printf "  %-20s %s\n" "Timezone:" "Asia/Kuala_Lumpur (GMT+8)"
  echo "  ───────────────────────────────────────────────────────────────"
  echo -e "\n  Press any key to return..."; read -n1
}

while true; do
  show_header
  echo -e "  ${BOLD}${YELLOW}MAIN MENU${NC}"
  echo "  ───────────────────────────────────────────────────────────────"
  echo "  [1] Service Status"
  echo "  [2] Add User"
  echo "  [3] Delete User"
  echo "  [4] List Users"
  echo "  [5] Service Control (Restart)"
  echo "  [6] Show Credentials"
  echo "  [7] System Information"
  echo "  [0] Exit"
  echo "  ───────────────────────────────────────────────────────────────"
  read -rp "  Choice: " CHOICE
  case $CHOICE in
    1) show_status ;;
    2) add_user_menu ;;
    3) del_user_menu ;;
    4) list_users_menu ;;
    5) service_control_menu ;;
    6) show_credentials ;;
    7) system_info_menu ;;
    0) clear; exit 0 ;;
    *) echo -e "  ${RED}Invalid option${NC}"; sleep 1 ;;
  esac
done
