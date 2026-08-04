#!/usr/bin/env bash

configure_ufw() {
    require_root
    command -v ufw >/dev/null 2>&1 || apt_install ufw
    local ssh_port="${SSHPLUS_SSH_PORT:-22}"
    ufw allow "${ssh_port}/tcp"
    if ! ufw status | grep -q '^Status: active'; then
        confirm "Ativar o UFW agora?" && ufw --force enable
    fi
    ok "Regra do OpenSSH aplicada no UFW."
}

install_fail2ban() {
    require_root
    apt_install fail2ban || { error 'Falha ao instalar Fail2ban.'; return 1; }
    install -d -m 0755 /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshplus.local <<CONF
[sshd]
enabled = true
port = ${SSHPLUS_SSH_PORT:-22}
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
CONF
    systemctl enable --now fail2ban
    systemctl restart fail2ban
    ok "Fail2ban instalado e configurado."
}

apply_network_tuning() {
    require_root
    cat > /etc/sysctl.d/99-sshplus-network.conf <<'CONF'
# Ajustes conservadores para servidores SSH/VPN modernos.
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
fs.file-max = 1048576
CONF
    sysctl --system >/dev/null
    ok "Ajustes de rede aplicados."
}

security_audit() {
    header 'Auditoria rápida de segurança'
    printf 'OpenSSH: %s\n' "$(service_status_text "$(ssh_unit)")"
    printf 'UFW: %s\n' "$(ufw status 2>/dev/null | head -1 || echo 'não instalado')"
    printf 'Fail2ban: %s\n' "$(service_status_text fail2ban.service)"
    printf 'Atualizações pendentes: %s\n' "$(apt-get -s upgrade 2>/dev/null | awk '/^Inst /{n++} END{print n+0}')"
    printf 'Autenticação root: %s\n' "$(/usr/sbin/sshd -T 2>/dev/null | awk '$1=="permitrootlogin"{print $2; exit}')"
    printf 'Autenticação por senha: %s\n' "$(/usr/sbin/sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2; exit}')"
    printf 'Versão OpenSSH: %s\n' "$(ssh -V 2>&1 | head -n 1)"
    printf '\nÚltimos acessos:\n'
    command -v last >/dev/null 2>&1 && last -n 8 -a 2>/dev/null || echo 'Comando last indisponível.'
}

security_menu() {
    local option
    while true; do
        header 'Segurança e otimização'
        printf '  1) Auditoria rápida\n  2) Configurar UFW\n  3) Instalar/configurar Fail2ban\n'
        printf '  4) Aplicar ajustes conservadores de rede\n  5) Atualizar pacotes do sistema\n  0) Voltar\n\n'
        read -r -p 'Opção: ' option
        case "$option" in
            1) security_audit; pause ;;
            2) configure_ufw; pause ;;
            3) install_fail2ban; pause ;;
            4) apply_network_tuning; pause ;;
            5) require_root; confirm 'Atualizar todos os pacotes instalados agora?' && { apt_update_once && DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 upgrade -y; }; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
