#!/usr/bin/env bash
set -euo pipefail
umask 027

PURGE_DATA=0; ASSUME_YES=0
usage(){ cat <<'USAGE'
Uso: sudo ./uninstall.sh [opções]
  -y, --yes       não solicitar confirmação
  --purge-data    remover configurações, SQLite, logs, chaves e credenciais
  -h, --help      exibir esta ajuda
USAGE
}
while (( $# > 0 )); do
 case "$1" in -y|--yes) ASSUME_YES=1;; --purge-data) PURGE_DATA=1;; -h|--help) usage; exit 0;; *) echo "Opção desconhecida: $1" >&2; exit 2;; esac; shift
done
[[ $EUID -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
if (( ASSUME_YES == 0 )); then read -r -p 'Remover o SSHPlus Manager? Os usuários Linux serão preservados. [s/N]: ' answer; [[ "$answer" =~ ^[sS]([iI][mM])?$ ]] || exit 0; fi

systemctl disable --now sshplus-expirer.timer sshplus-limiter.timer sshplus-metrics.timer 2>/dev/null || true
systemctl disable --now sshplus-openvpn-nat.service sshplus-badvpn.service sshplus-slowdns.service 2>/dev/null || true
systemctl disable --now openvpn-server@sshplus.service openvpn@sshplus.service 2>/dev/null || true
rm -f /etc/systemd/system/sshplus-expirer.{service,timer} /etc/systemd/system/sshplus-limiter.{service,timer} /etc/systemd/system/sshplus-metrics.{service,timer}
rm -f /etc/systemd/system/sshplus-openvpn-nat.service /etc/systemd/system/sshplus-badvpn.service /etc/systemd/system/sshplus-slowdns.service
rm -f /etc/nftables.d/sshplus-openvpn.nft /etc/sysctl.d/99-sshplus-network.conf /etc/sysctl.d/99-sshplus-openvpn.conf
rm -f /etc/fail2ban/jail.d/sshplus.local /etc/logrotate.d/sshplus /etc/tmpfiles.d/sshplus.conf
rm -f /etc/ssh/sshd_config.d/00-sshplus.conf
rm -f /etc/nginx/sites-enabled/sshplus-panel /etc/nginx/sites-available/sshplus-panel
rm -f /etc/sudoers.d/sshplus-api /etc/php/8.5/fpm/conf.d/99-sshplus.ini
rm -f /usr/local/sbin/sshplus /usr/local/bin/menu /usr/local/sbin/sshplus-agent /usr/local/sbin/sshplus-healthcheck
rm -f /usr/local/sbin/sshplus-badvpn /usr/local/sbin/badvpn /usr/local/sbin/sshplus-slowdns /usr/local/sbin/slowdns
rm -f /usr/local/sbin/badvpn-udpgw /usr/local/bin/badvpn-udpgw /usr/local/sbin/dnstt-server /usr/local/bin/dnstt-client
rm -rf /usr/local/share/licenses/sshplus-badvpn /usr/local/share/sshplus-slowdns /opt/sshplus

if (( PURGE_DATA == 1 )); then
 rm -rf /etc/sshplus /var/lib/sshplus /var/log/sshplus /etc/slowdns /root/sshplus-clients /root/sshplus-panel-credentials.txt
 userdel sshplus-slowdns 2>/dev/null || true; groupdel sshplus-slowdns 2>/dev/null || true
 groupdel sshplus-api 2>/dev/null || true
fi
systemctl daemon-reload
systemctl restart php8.5-fpm.service nginx.service fail2ban.service 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true
if [[ -x /usr/sbin/sshd ]] && /usr/sbin/sshd -t; then systemctl restart ssh.service 2>/dev/null || systemctl restart sshd.service 2>/dev/null || true; fi
if (( PURGE_DATA == 1 )); then echo 'SSHPlus removido com dados e credenciais. Usuários Linux preservados.'; else echo 'SSHPlus removido. Dados, chaves, logs e backups preservados.'; fi
