#!/usr/bin/env bash

known_services() {
    cat <<'SERVICES'
ssh.service|OpenSSH
squid.service|Squid
stunnel4.service|Stunnel
sslh.service|SSLH
dropbear.service|Dropbear
openvpn-server@sshplus.service|OpenVPN
fail2ban.service|Fail2ban
nginx.service|Painel Nginx
php8.5-fpm.service|PHP 8.5 FPM
cron.service|Cron
sshplus-openvpn-nat.service|NAT OpenVPN
sshplus-badvpn.service|BadVPN UDPGW
sshplus-slowdns.service|SlowDNS / DNSTT
sshplus-metrics.timer|Coleta de métricas
SERVICES
}

show_services() {
    header 'Serviços do servidor'
    printf '%-24s %-15s %-12s\n' 'SERVIÇO' 'UNIDADE' 'STATUS'
    printf '%-24s %-15s %-12s\n' '------------------------' '---------------' '------------'
    while IFS='|' read -r unit label; do
        if [[ "$unit" == 'ssh.service' ]] && ! service_exists ssh.service; then
            unit='sshd.service'
        fi
        printf '%-24s %-15s %-12s\n' "$label" "$unit" "$(service_status_text "$unit")"
    done < <(known_services)
}

restart_service_menu() {
    require_root
    local units=() labels=() unit label i=1 choice
    header 'Reiniciar serviço'
    while IFS='|' read -r unit label; do
        if [[ "$unit" == 'ssh.service' ]]; then unit="$(ssh_unit)"; fi
        if service_exists "$unit"; then
            units+=("$unit"); labels+=("$label")
            printf '  %d) %s (%s)\n' "$i" "$label" "$unit"
            ((i++))
        fi
    done < <(known_services)
    printf '  0) Voltar\n\n'
    read -r -p 'Opção: ' choice
    [[ "$choice" == 0 ]] && return
    [[ "$choice" =~ ^[0-9]+$ ]] || { error "Opção inválida."; return; }
    (( choice >= 1 && choice <= ${#units[@]} )) || { error "Opção inválida."; return; }
    unit="${units[$((choice-1))]}"
    if [[ "$unit" == "$(ssh_unit)" ]]; then
        restart_ssh_safe
    else
        systemctl restart "$unit" && ok "${labels[$((choice-1))]} reiniciado."
    fi
}

show_listening_ports() {
    header 'Portas em escuta'
    ss -lntup
}

services_menu() {
    local option
    while true; do
        header 'Serviços e portas'
        printf '  1) Exibir status\n  2) Reiniciar serviço\n  3) Exibir portas em escuta\n  4) Validar OpenSSH\n  0) Voltar\n\n'
        read -r -p 'Opção: ' option
        case "$option" in
            1) show_services; pause ;;
            2) restart_service_menu; pause ;;
            3) show_listening_ports; pause ;;
            4) validate_sshd && ok 'Configuração OpenSSH válida.' || error 'Configuração inválida.'; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
