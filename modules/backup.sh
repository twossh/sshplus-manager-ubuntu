#!/usr/bin/env bash

backup_paths() {
    local paths=("etc/sshplus" "var/lib/sshplus" "etc/ssh/sshd_config.d/00-sshplus.conf")
    [[ -d /etc/openvpn/sshplus ]] && paths+=("etc/openvpn/sshplus")
    [[ -f /etc/openvpn/server/sshplus.conf ]] && paths+=("etc/openvpn/server/sshplus.conf")
    [[ -L /etc/openvpn/sshplus.conf ]] && paths+=("etc/openvpn/sshplus.conf")
    [[ -d /root/sshplus-clients ]] && paths+=("root/sshplus-clients")
    [[ -d /etc/slowdns ]] && paths+=("etc/slowdns")
    [[ -f /etc/fail2ban/jail.d/sshplus.local ]] && paths+=("etc/fail2ban/jail.d/sshplus.local")
    [[ -f /etc/nginx/sites-available/sshplus-panel ]] && paths+=("etc/nginx/sites-available/sshplus-panel")
    [[ -f /etc/sudoers.d/sshplus-api ]] && paths+=("etc/sudoers.d/sshplus-api")
    [[ -f /etc/nftables.d/sshplus-openvpn.nft ]] && paths+=("etc/nftables.d/sshplus-openvpn.nft")
    [[ -f /etc/systemd/system/sshplus-openvpn-nat.service ]] && paths+=("etc/systemd/system/sshplus-openvpn-nat.service")
    printf '%s\n' "${paths[@]}"
}

create_backup_file() {
    require_root
    local source="${1:-cli}" actor="${2:-root}" stamp file sha size
    stamp="$(date '+%Y%m%d-%H%M%S')"
    file="${SSHPLUS_BACKUP_DIR}/sshplus-${stamp}.tar.gz"
    install -d -m 0700 "$SSHPLUS_BACKUP_DIR"
    mapfile -t paths < <(backup_paths)
    tar --ignore-failed-read --numeric-owner -C / -czf "$file" "${paths[@]}" 2>/dev/null || { rm -f "$file"; return 1; }
    tar -tzf "$file" >/dev/null || { rm -f "$file"; return 1; }
    chmod 0600 "$file"
    sha="$(sha256sum "$file" | awk '{print $1}')"; size="$(stat -c %s "$file")"
    if declare -F db_exec >/dev/null 2>&1; then
        db_exec "INSERT OR REPLACE INTO backups(filename,created_at,size_bytes,sha256,status) VALUES('$(sqlite_escape "$file")',$(date +%s),$size,'$sha','ready');" >/dev/null || true
        audit_log "$actor" "$source" backup.create "$file" 1 "sha256=$sha tamanho=$size"
    fi
    printf '%s\n' "$file"
}

create_backup() {
    local file
    if file="$(create_backup_file cli root)"; then ok "Backup criado: $file"; else error 'Falha ao criar o backup.'; fi
}

backup_list_json() {
    local first=1 file sha size created
    printf '{"ok":true,"data":['
    shopt -s nullglob
    for file in "$SSHPLUS_BACKUP_DIR"/sshplus-*.tar.gz; do
        sha="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"; size="$(stat -c %s "$file")"; created="$(stat -c %Y "$file")"
        (( first == 1 )) || printf ','; first=0
        jq -cn --arg file "$file" --arg sha256 "$sha" --argjson size "$size" --argjson created_at "$created" '{file:$file,sha256:$sha256,size_bytes:$size,created_at:$created_at}'
    done
    shopt -u nullglob
    printf ']}\n'
}

list_backups() {
    header 'Backups disponíveis'
    ls -lh "$SSHPLUS_BACKUP_DIR"/sshplus-*.tar.gz 2>/dev/null || echo 'Nenhum backup encontrado.'
}

restore_backup_file() {
    require_root
    local file="$1" actor="${2:-root}" source="${3:-cli}"
    [[ -f "$file" && "$file" == "$SSHPLUS_BACKUP_DIR"/* ]] || return 2
    tar -tzf "$file" >/dev/null 2>&1 || return 2
    tar -tzf "$file" | grep -Eq '(^/|(^|/)\.\.(/|$))' && return 2
    tar -xzf "$file" -C /
    validate_sshd || return 1
    systemctl daemon-reload
    systemctl restart "$(ssh_unit)"
    systemctl restart sshplus-limiter.timer sshplus-expirer.timer 2>/dev/null || true
    systemctl restart nginx.service php8.5-fpm.service 2>/dev/null || true
    systemctl restart sshplus-badvpn.service sshplus-slowdns.service 2>/dev/null || true
    audit_log "$actor" "$source" backup.restore "$file" 1
}

restore_backup() {
    local file
    read -r -e -p 'Arquivo de backup: ' file
    [[ -f "$file" ]] || { error 'Arquivo não encontrado.'; return; }
    confirm 'Restaurar este backup sobre a configuração atual?' || return
    restore_backup_file "$file" root cli && ok 'Backup restaurado.' || error 'Falha ao restaurar o backup.'
}

backup_menu() {
    local option
    while true; do
        header 'Backup e restauração'
        printf '  1) Criar backup\n  2) Listar backups\n  3) Restaurar backup\n  0) Voltar\n\n'
        read -r -p 'Opção: ' option || return
        case "$option" in
            1) create_backup; pause ;; 2) list_backups; pause ;; 3) restore_backup; pause ;; 0) return ;; *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
