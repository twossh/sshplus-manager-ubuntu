#!/usr/bin/env bash

panel_url() {
    local listen="${SSHPLUS_PANEL_LISTEN:-127.0.0.1:8088}"
    printf 'http://%s\n' "$listen"
}

panel_status() {
    header 'Painel web e API REST' 'Acesso local seguro por padrão'
    printf '  Nginx:       %s\n' "$(service_status_text nginx.service)"
    local php_version php_service
    php_version="$(sshplus_php_version 2>/dev/null || printf '?')"
    php_service="$(sshplus_php_fpm_service 2>/dev/null || printf 'php-fpm.service')"
    printf '  PHP %s:     %s\n' "$php_version" "$(service_status_text "$php_service")"
    printf '  Endereço:    %s\n' "$(panel_url)"
    printf '  Banco:       %s\n' "$SSHPLUS_DB"
    printf '  Credenciais: /root/sshplus-panel-credentials.txt\n'
    if [[ -x "$SSHPLUS_HOME/bin/sshplus-panel-public" ]]; then
        local public_status public_domain
        public_status='no'; public_domain=''
        if [[ -r "$SSHPLUS_CONFIG_DIR/panel-public.conf" ]]; then
            public_status="$(sed -nE 's/^SSHPLUS_PANEL_PUBLIC_ENABLED="?([^"]+)"?$/\1/p' "$SSHPLUS_CONFIG_DIR/panel-public.conf" | tail -n1)"
            public_domain="$(sed -nE 's/^SSHPLUS_PANEL_PUBLIC_DOMAIN="?([^"]*)"?$/\1/p' "$SSHPLUS_CONFIG_DIR/panel-public.conf" | tail -n1)"
        fi
        printf '  HTTPS público: %s' "${public_status:-no}"
        [[ -n "$public_domain" ]] && printf ' — https://%s' "$public_domain"
        printf '\n'
    fi
    printf '\n'
    local panel_listen panel_port
    panel_listen="${SSHPLUS_PANEL_LISTEN:-127.0.0.1:8088}"
    panel_port="${panel_listen##*:}"; panel_port="${panel_port%]}"
    printf 'Acesso recomendado a partir do computador local:\n'
    printf '  ssh -L %s:127.0.0.1:%s usuario@IP_DA_VPS\n' "$panel_port" "$panel_port"
    printf '  abra http://127.0.0.1:%s no navegador\n' "$panel_port"
}

panel_reset_password() {
    require_root
    local username password hash auth_file auth_tmp listen port php_cli public_domain public_enabled
    username="$(prompt_value 'Usuário do painel' 'admin')" || return
    valid_username "$username" || { error 'Usuário inválido.'; return; }
    password="$(prompt_secret_confirmed 'Nova senha')" || return
    valid_password "$password" || { error 'Use no mínimo 8 caracteres.'; return; }
    php_cli="$(sshplus_php_cli_binary)"
    hash="$("$php_cli" -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$password")"
    auth_file="$SSHPLUS_CONFIG_DIR/panel-auth.json"
    auth_tmp="$(mktemp "$SSHPLUS_CONFIG_DIR/.panel-auth.XXXXXX")"
    jq -n --arg username "$username" --arg password_hash "$hash" \
        '{version:1,accounts:[{username:$username,password_hash:$password_hash,role:"admin",active:true}]}' > "$auth_tmp"
    install -m 0640 -o root -g sshplus-api "$auth_tmp" "$auth_file"
    rm -f "$auth_tmp"
    db_api_user_upsert "$username" "$hash" admin
    listen="${SSHPLUS_PANEL_LISTEN:-127.0.0.1:8088}"
    port="${listen##*:}"; port="${port%]}"
    cat > /root/sshplus-panel-credentials.txt <<CRED
SSHPlus Manager $(sshplus_version)
Usuário: $username
Senha: $password
Acesso local: http://$listen
Túnel SSH: ssh -L $port:127.0.0.1:$port usuario@IP_DA_VPS
CRED
    if [[ -r "$SSHPLUS_CONFIG_DIR/panel-public.conf" ]]; then
        public_domain="$(sed -nE 's/^SSHPLUS_PANEL_PUBLIC_DOMAIN="?([^"]*)"?$/\1/p' "$SSHPLUS_CONFIG_DIR/panel-public.conf" | tail -n1)"
        public_enabled="$(sed -nE 's/^SSHPLUS_PANEL_PUBLIC_ENABLED="?([^"]+)"?$/\1/p' "$SSHPLUS_CONFIG_DIR/panel-public.conf" | tail -n1)"
        [[ "$public_enabled" == yes && -n "$public_domain" ]] && printf 'Acesso HTTPS: https://%s\n' "$public_domain" >> /root/sshplus-panel-credentials.txt
    fi
    chmod 0600 /root/sshplus-panel-credentials.txt
    audit_log root cli panel.password "$username" 1
    ok 'Credencial atualizada.'
}

panel_show_credentials() {
    require_root
    local file='/root/sshplus-panel-credentials.txt'
    [[ -r "$file" ]] && cat "$file" || warn 'O arquivo inicial não existe; redefina a senha pelo menu.'
}

panel_menu() {
    local option domain email
    while true; do
        header 'Painel web e API REST'
        printf '  1) Exibir status e instruções de acesso\n'
        printf '  2) Redefinir usuário/senha administrativa\n'
        printf '  3) Exibir credencial inicial\n'
        printf '  4) Reiniciar Nginx e PHP-FPM\n'
        printf '  5) Reparar e validar o painel\n'
        printf '  6) Status do domínio/HTTPS público\n'
        printf '  7) Pré-verificar domínio e requisitos\n'
        printf '  8) Ativar domínio/HTTPS público\n'
        printf '  9) Desativar domínio/HTTPS público\n'
        printf ' 10) Reaplicar configuração HTTPS\n'
        printf ' 11) Renovar certificados agora\n'
        printf ' 12) Simular renovação do certificado\n'
        printf '  0) Voltar\n\n'
        read -r -p 'Opção: ' option || return
        case "$option" in
            1) panel_status; pause ;;
            2) panel_reset_password; pause ;;
            3) panel_show_credentials; pause ;;
            4) systemctl restart "$(sshplus_php_fpm_service)" nginx.service && ok 'Painel reiniciado.'; pause ;;
            5) "$SSHPLUS_HOME/bin/sshplus-panel-repair"; pause ;;
            6) "$SSHPLUS_HOME/bin/sshplus-panel-public" status; pause ;;
            7)
                domain="$(prompt_value 'Domínio do painel (ex.: painel.exemplo.com)' '')" || continue
                "$SSHPLUS_HOME/bin/sshplus-panel-public" preflight --domain "$domain"
                pause
                ;;
            8)
                domain="$(prompt_value 'Domínio do painel (ex.: painel.exemplo.com)' '')" || continue
                email="$(prompt_value 'E-mail para o Let’s Encrypt' '')" || continue
                "$SSHPLUS_HOME/bin/sshplus-panel-public" enable --domain "$domain" --email "$email"
                pause
                ;;
            9) "$SSHPLUS_HOME/bin/sshplus-panel-public" disable; pause ;;
            10) "$SSHPLUS_HOME/bin/sshplus-panel-public" reconfigure; pause ;;
            11) "$SSHPLUS_HOME/bin/sshplus-panel-public" renew; pause ;;
            12) "$SSHPLUS_HOME/bin/sshplus-panel-public" test-renewal; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
