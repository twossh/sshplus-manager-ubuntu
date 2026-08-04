#!/usr/bin/env bash

DNSTT_VERSION='v1.20260501.0'
DNSTT_MODULE='www.bamsoftware.com/git/dnstt.git'
SLOWDNS_SERVER_BINARY='/usr/local/sbin/dnstt-server'
SLOWDNS_CLIENT_BINARY='/usr/local/bin/dnstt-client'
SLOWDNS_UNIT='sshplus-slowdns.service'
SLOWDNS_ENV='/etc/sshplus/slowdns.env'
SLOWDNS_KEY_DIR='/etc/slowdns'
SLOWDNS_PRIVATE_KEY='/etc/slowdns/server.key'
SLOWDNS_PUBLIC_KEY='/etc/slowdns/server.pub'
SLOWDNS_USER='sshplus-slowdns'
SLOWDNS_GROUP='sshplus-slowdns'
SLOWDNS_BUILDINFO='/usr/local/share/sshplus-slowdns/BUILDINFO'
SLOWDNS_CLIENT_INFO='/root/sshplus-clients/slowdns-info.txt'
SLOWDNS_LEGACY_DIR='/etc/SSHPlus/dns'

slowdns_valid_domain() {
    local domain="${1,,}" label
    [[ -n "$domain" && ${#domain} -le 253 && "$domain" == *.* && "$domain" != .* && "$domain" != *. ]] || return 1
    IFS='.' read -r -a labels <<< "$domain"
    for label in "${labels[@]}"; do
        [[ -n "$label" && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
    done
}

slowdns_valid_ipv4() {
    local ip="$1" octet
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
}

slowdns_valid_listen() {
    local value="$1" ip port
    [[ "$value" =~ ^(([0-9]{1,3}\.){3}[0-9]{1,3}):([0-9]{1,5})$ ]] || return 1
    ip="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[3]}"
    slowdns_valid_ipv4 "$ip" || return 1
    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

slowdns_valid_upstream() {
    local value="$1" port
    [[ "$value" =~ ^127\.0\.0\.1:([0-9]{1,5})$ ]] || return 1
    port="${BASH_REMATCH[1]}"
    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

slowdns_primary_ipv4() {
    local ip
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
    slowdns_valid_ipv4 "$ip" && printf '%s\n' "$ip" || printf '0.0.0.0\n'
}

slowdns_default_upstream() {
    local port
    port="${SSHPLUS_SSH_PORT:-}"
    [[ "$port" =~ ^[0-9]+$ ]] || port="$(/usr/sbin/sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
    port="${port:-22}"
    printf '127.0.0.1:%s\n' "$port"
}

slowdns_installed() {
    [[ -x "$SLOWDNS_SERVER_BINARY" && -x "$SLOWDNS_CLIENT_BINARY" ]] || return 1
    go version -m "$SLOWDNS_SERVER_BINARY" 2>/dev/null | grep -Fq "$DNSTT_VERSION"
}

slowdns_version_text() {
    if [[ -x "$SLOWDNS_SERVER_BINARY" ]]; then
        go version -m "$SLOWDNS_SERVER_BINARY" 2>/dev/null | awk '$1=="mod"{print $3; exit}'
    else
        printf 'não instalado\n'
    fi
}

slowdns_create_service_user() {
    getent group "$SLOWDNS_GROUP" >/dev/null 2>&1 || groupadd --system "$SLOWDNS_GROUP"
    id -u "$SLOWDNS_USER" >/dev/null 2>&1 || useradd \
        --system --gid "$SLOWDNS_GROUP" --home-dir /nonexistent \
        --shell /usr/sbin/nologin --no-create-home "$SLOWDNS_USER"
}

slowdns_write_default_config() {
    local listen upstream
    install -d -m 0750 /etc/sshplus
    [[ -f "$SLOWDNS_ENV" ]] && return 0
    listen="$(slowdns_primary_ipv4):53"
    upstream="$(slowdns_default_upstream)"
    cat > "$SLOWDNS_ENV" <<CONF
SLOWDNS_LISTEN_ADDR=$listen
SLOWDNS_MTU=1232
SLOWDNS_DOMAIN=
SLOWDNS_UPSTREAM_ADDR=$upstream
CONF
    chmod 0640 "$SLOWDNS_ENV"
}

slowdns_load_config() {
    local config_file="${1:-$SLOWDNS_ENV}"
    SLOWDNS_LISTEN_ADDR=''
    SLOWDNS_MTU=''
    SLOWDNS_DOMAIN=''
    SLOWDNS_UPSTREAM_ADDR=''
    [[ -r "$config_file" ]] || return 1
    load_env_file "$config_file" 'SLOWDNS_' || return 1
}

slowdns_validate_config() {
    local config_file="${1:-$SLOWDNS_ENV}"
    slowdns_load_config "$config_file" || { error "Configuração ausente ou inválida: $config_file"; return 1; }
    slowdns_valid_listen "${SLOWDNS_LISTEN_ADDR:-}" || { error 'Endereço de escuta inválido. Use IPv4:porta.'; return 1; }
    [[ "${SLOWDNS_MTU:-}" =~ ^[0-9]+$ ]] && (( 10#$SLOWDNS_MTU >= 512 && 10#$SLOWDNS_MTU <= 1232 )) || {
        error 'MTU inválido. Use um valor entre 512 e 1232.'; return 1;
    }
    slowdns_valid_domain "${SLOWDNS_DOMAIN:-}" || { error 'Domínio do túnel inválido ou ainda não configurado.'; return 1; }
    slowdns_valid_upstream "${SLOWDNS_UPSTREAM_ADDR:-}" || {
        error 'O destino deve ser um serviço TCP local no formato 127.0.0.1:porta.'; return 1;
    }
}


slowdns_migrate_legacy() {
    local legacy_auto legacy_domain legacy_upstream legacy_port backup_dir temp
    [[ -d "$SLOWDNS_LEGACY_DIR" ]] || return 0
    backup_dir="/var/backups/sshplus/slowdns/legacy-$(date '+%Y%m%d-%H%M%S')"
    install -d -m 0700 "$backup_dir"
    cp -a "$SLOWDNS_LEGACY_DIR" "$backup_dir/"

    slowdns_create_service_user
    install -d -o root -g "$SLOWDNS_GROUP" -m 0750 "$SLOWDNS_KEY_DIR"
    if [[ ! -s "$SLOWDNS_PRIVATE_KEY" && -s "$SLOWDNS_LEGACY_DIR/server.key" ]]; then
        install -o root -g "$SLOWDNS_GROUP" -m 0640 "$SLOWDNS_LEGACY_DIR/server.key" "$SLOWDNS_PRIVATE_KEY"
    fi
    if [[ ! -s "$SLOWDNS_PUBLIC_KEY" && -s "$SLOWDNS_LEGACY_DIR/server.pub" ]]; then
        install -o root -g "$SLOWDNS_GROUP" -m 0644 "$SLOWDNS_LEGACY_DIR/server.pub" "$SLOWDNS_PUBLIC_KEY"
    fi

    legacy_auto="$SLOWDNS_LEGACY_DIR/autodns"
    slowdns_load_config || true
    if [[ -f "$legacy_auto" && -z "${SLOWDNS_DOMAIN:-}" ]]; then
        legacy_domain="$(awk '{for(i=1;i<=NF;i++) if($i ~ /server\.key$/){print $(i+1); exit}}' "$legacy_auto")"
        legacy_upstream="$(awk '{for(i=1;i<=NF;i++) if($i ~ /server\.key$/){print $(i+2); exit}}' "$legacy_auto")"
        legacy_port="${legacy_upstream##*:}"
        if slowdns_valid_domain "$legacy_domain" && [[ "$legacy_port" =~ ^[0-9]+$ ]] && (( 10#$legacy_port >= 1 && 10#$legacy_port <= 65535 )); then
            temp="$(mktemp "${SLOWDNS_ENV}.XXXXXX")"
            cat > "$temp" <<CONF
SLOWDNS_LISTEN_ADDR=$(slowdns_primary_ipv4):53
SLOWDNS_MTU=1232
SLOWDNS_DOMAIN=${legacy_domain,,}
SLOWDNS_UPSTREAM_ADDR=127.0.0.1:$legacy_port
CONF
            chmod 0640 "$temp"
            mv -f "$temp" "$SLOWDNS_ENV"
        fi
    fi

    # Para somente o binário legado exato e remove sua chamada do autostart antigo.
    while read -r legacy_pid; do
        [[ "$legacy_pid" =~ ^[0-9]+$ ]] && kill -TERM "$legacy_pid" 2>/dev/null || true
    done < <(pgrep -f '^/etc/SSHPlus/dns/dns-server ' 2>/dev/null || true)
    if [[ -f /etc/autostart ]]; then
        cp -a /etc/autostart "$backup_dir/autostart.before"
        sed -i '\|/etc/SSHPlus/dns/autodns|d; /slow_dns/d' /etc/autostart
    fi
    info "SlowDNS legado preservado em $backup_dir e migrado quando possível."
}

slowdns_generate_keys() {
    slowdns_create_service_user
    install -d -o root -g "$SLOWDNS_GROUP" -m 0750 "$SLOWDNS_KEY_DIR"
    if [[ ! -s "$SLOWDNS_PRIVATE_KEY" || ! -s "$SLOWDNS_PUBLIC_KEY" ]]; then
        "$SLOWDNS_SERVER_BINARY" -gen-key \
            -privkey-file "$SLOWDNS_PRIVATE_KEY" \
            -pubkey-file "$SLOWDNS_PUBLIC_KEY" >/dev/null
    fi
    chown root:"$SLOWDNS_GROUP" "$SLOWDNS_PRIVATE_KEY" "$SLOWDNS_PUBLIC_KEY"
    chmod 0640 "$SLOWDNS_PRIVATE_KEY"
    chmod 0644 "$SLOWDNS_PUBLIC_KEY"
}

slowdns_export_client_info() {
    local public_ip pubkey
    slowdns_validate_config || return 1
    [[ -s "$SLOWDNS_PUBLIC_KEY" ]] || { error 'Chave pública não encontrada.'; return 1; }
    public_ip="$(get_public_ipv4)"
    pubkey="$(tr -d '\r\n' < "$SLOWDNS_PUBLIC_KEY")"
    install -d -m 0700 "$(dirname "$SLOWDNS_CLIENT_INFO")"
    cat > "$SLOWDNS_CLIENT_INFO" <<CONF
SSHPlus SlowDNS / DNSTT $DNSTT_VERSION

Zona delegada: $SLOWDNS_DOMAIN
IP público informado: $public_ip
Escuta do servidor: $SLOWDNS_LISTEN_ADDR/udp
Destino TCP local: $SLOWDNS_UPSTREAM_ADDR
MTU: $SLOWDNS_MTU
Chave pública: $pubkey

DNS necessário no provedor do domínio:
1. Crie um registro A, por exemplo ns1.seudominio.com, apontando para $public_ip.
2. Delegue a zona $SLOWDNS_DOMAIN com um registro NS apontando para esse hostname.
3. Não use proxy/CDN no registro A do nameserver.

Exemplo de cliente UDP usando um resolvedor recursivo:
dnstt-client -udp 1.1.1.1:53 -pubkey $pubkey $SLOWDNS_DOMAIN 127.0.0.1:2222

Depois conecte o cliente SSH ao endereço 127.0.0.1 e porta 2222.
Use somente em redes, servidores e domínios que você administra ou tem autorização para testar.
CONF
    chmod 0600 "$SLOWDNS_CLIENT_INFO"
    ok "Informações do cliente salvas em $SLOWDNS_CLIENT_INFO"
}

install_slowdns() (
    require_root
    local work module_json source_dir module_sum gomod_sum go_version backup_dir
    info "Compilando DNSTT ${DNSTT_VERSION} a partir do módulo oficial."
    apt_install golang-go ca-certificates jq || {
        error 'Não foi possível instalar Go e as dependências.'; return 1;
    }

    work="$(mktemp -d /tmp/sshplus-slowdns.XXXXXX)"
    trap 'rm -rf "${work:-}"' EXIT INT TERM
    install -d -m 0755 "$work/bin" "$work/gopath"
    export GOPATH="$work/gopath"
    export GOBIN="$work/bin"
    export GOPROXY='https://proxy.golang.org,direct'
    export GOSUMDB='sum.golang.org'
    export CGO_ENABLED=0

    module_json="$(go mod download -json "${DNSTT_MODULE}@${DNSTT_VERSION}")" || {
        error 'Falha ao baixar o módulo oficial do DNSTT.'; return 1;
    }
    source_dir="$(jq -r '.Dir // empty' <<< "$module_json")"
    module_sum="$(jq -r '.Sum // empty' <<< "$module_json")"
    gomod_sum="$(jq -r '.GoModSum // empty' <<< "$module_json")"
    [[ -n "$source_dir" && -d "$source_dir" && -n "$module_sum" && -n "$gomod_sum" ]] || {
        error 'O módulo recebido não apresentou metadados de integridade válidos.'; return 1;
    }

    go install "${DNSTT_MODULE}/dnstt-server@${DNSTT_VERSION}" || { error 'Falha ao compilar dnstt-server.'; return 1; }
    go install "${DNSTT_MODULE}/dnstt-client@${DNSTT_VERSION}" || { error 'Falha ao compilar dnstt-client.'; return 1; }
    [[ -x "$work/bin/dnstt-server" && -x "$work/bin/dnstt-client" ]] || {
        error 'Os binários compilados não foram encontrados.'; return 1;
    }
    go version -m "$work/bin/dnstt-server" | grep -Fq "$DNSTT_VERSION" || {
        error 'A versão compilada do servidor não corresponde à versão fixada.'; return 1;
    }
    go version -m "$work/bin/dnstt-client" | grep -Fq "$DNSTT_VERSION" || {
        error 'A versão compilada do cliente não corresponde à versão fixada.'; return 1;
    }

    backup_dir="/var/backups/sshplus/slowdns/$(date '+%Y%m%d-%H%M%S')"
    install -d -m 0700 "$backup_dir"
    [[ -e "$SLOWDNS_SERVER_BINARY" ]] && cp -a "$SLOWDNS_SERVER_BINARY" "$backup_dir/" || true
    [[ -e "$SLOWDNS_CLIENT_BINARY" ]] && cp -a "$SLOWDNS_CLIENT_BINARY" "$backup_dir/" || true
    [[ -d "$SLOWDNS_KEY_DIR" ]] && cp -a "$SLOWDNS_KEY_DIR" "$backup_dir/" || true
    [[ -f "$SLOWDNS_ENV" ]] && cp -a "$SLOWDNS_ENV" "$backup_dir/" || true

    install -m 0755 "$work/bin/dnstt-server" "$SLOWDNS_SERVER_BINARY"
    install -m 0755 "$work/bin/dnstt-client" "$SLOWDNS_CLIENT_BINARY"
    install -d -m 0755 "$(dirname "$SLOWDNS_BUILDINFO")"
    go_version="$(go version)"
    cat > "$SLOWDNS_BUILDINFO" <<CONF
component=dnstt
module=$DNSTT_MODULE
version=$DNSTT_VERSION
module_sum=$module_sum
gomod_sum=$gomod_sum
compiler=$go_version
built_at=$(date --iso-8601=seconds)
server_sha256=$(sha256sum "$SLOWDNS_SERVER_BINARY" | awk '{print $1}')
client_sha256=$(sha256sum "$SLOWDNS_CLIENT_BINARY" | awk '{print $1}')
CONF
    chmod 0644 "$SLOWDNS_BUILDINFO"
    for license_file in COPYING LICENSE LICENSE.txt README README.md; do
        [[ -f "$source_dir/$license_file" ]] && install -m 0644 "$source_dir/$license_file" "$(dirname "$SLOWDNS_BUILDINFO")/$license_file"
    done

    slowdns_write_default_config
    slowdns_migrate_legacy
    slowdns_generate_keys
    systemctl daemon-reload
    ok "DNSTT ${DNSTT_VERSION} instalado e verificado."
    info "Backup da instalação anterior: $backup_dir"

    slowdns_load_config || true
    if slowdns_valid_domain "${SLOWDNS_DOMAIN:-}" && slowdns_validate_config; then
        systemctl enable --now "$SLOWDNS_UNIT" || {
            error 'O DNSTT foi instalado, mas o serviço não iniciou.'
            systemctl --no-pager --full status "$SLOWDNS_UNIT" || true
            return 1
        }
        slowdns_export_client_info || true
    else
        warn 'O domínio ainda precisa ser configurado. Use a opção Configurar antes de iniciar o serviço.'
    fi
)

configure_slowdns() {
    require_root
    local current_listen current_mtu current_domain current_upstream
    local listen mtu domain upstream temp
    slowdns_write_default_config
    slowdns_load_config || return 1
    current_listen="${SLOWDNS_LISTEN_ADDR:-$(slowdns_primary_ipv4):53}"
    current_mtu="${SLOWDNS_MTU:-1232}"
    current_domain="${SLOWDNS_DOMAIN:-}"
    current_upstream="${SLOWDNS_UPSTREAM_ADDR:-$(slowdns_default_upstream)}"

    printf '\nInforme a zona delegada ao túnel, por exemplo: t.seudominio.com\n'
    read -r -p "Zona SlowDNS [${current_domain:-não configurada}]: " domain
    domain="${domain:-$current_domain}"; domain="${domain,,}"
    read -r -p "IPv4 e porta UDP de escuta [$current_listen]: " listen; listen="${listen:-$current_listen}"
    read -r -p "Destino TCP local [$current_upstream]: " upstream; upstream="${upstream:-$current_upstream}"
    read -r -p "MTU [$current_mtu]: " mtu; mtu="${mtu:-$current_mtu}"

    temp="$(mktemp "${SLOWDNS_ENV}.XXXXXX")"
    cat > "$temp" <<CONF
SLOWDNS_LISTEN_ADDR=$listen
SLOWDNS_MTU=$mtu
SLOWDNS_DOMAIN=$domain
SLOWDNS_UPSTREAM_ADDR=$upstream
CONF
    chmod 0640 "$temp"
    if ! slowdns_validate_config "$temp"; then
        rm -f "$temp"
        error 'Configuração rejeitada; o arquivo anterior foi preservado.'
        return 1
    fi
    mv -f "$temp" "$SLOWDNS_ENV"
    slowdns_load_config || return 1

    if [[ -x "$SLOWDNS_SERVER_BINARY" ]]; then
        slowdns_generate_keys
        systemctl daemon-reload
        if systemctl enable --now "$SLOWDNS_UNIT"; then
            systemctl restart "$SLOWDNS_UNIT"
            slowdns_export_client_info || true
            local port
            port="${SLOWDNS_LISTEN_ADDR##*:}"
            if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
                ufw allow "$port/udp" comment 'SSHPlus SlowDNS' >/dev/null || true
            fi
            ok 'Configuração aplicada e serviço iniciado.'
        else
            error 'Configuração salva, mas o serviço não iniciou.'
            systemctl --no-pager --full status "$SLOWDNS_UNIT" || true
            return 1
        fi
    else
        ok 'Configuração salva. Instale o SlowDNS para ativá-la.'
    fi
}

show_slowdns_info() {
    header 'SlowDNS / DNSTT'
    printf 'Versão esperada: %s\n' "$DNSTT_VERSION"
    printf 'Versão instalada: %s\n' "$(slowdns_version_text)"
    printf 'Serviço: %s\n\n' "$(service_status_text "$SLOWDNS_UNIT")"
    if slowdns_load_config; then
        printf 'Zona: %s\n' "${SLOWDNS_DOMAIN:-não configurada}"
        printf 'Escuta: %s/udp\n' "${SLOWDNS_LISTEN_ADDR:-não configurada}"
        printf 'Destino: %s/tcp\n' "${SLOWDNS_UPSTREAM_ADDR:-não configurado}"
        printf 'MTU: %s\n' "${SLOWDNS_MTU:-não configurado}"
    fi
    [[ -s "$SLOWDNS_PUBLIC_KEY" ]] && printf 'Chave pública: %s\n' "$(tr -d '\r\n' < "$SLOWDNS_PUBLIC_KEY")"
    printf '\n'
    systemctl --no-pager --full status "$SLOWDNS_UNIT" 2>/dev/null || true
    printf '\nPorta UDP em escuta:\n'
    ss -lunp 2>/dev/null | grep -F 'dnstt-server' || echo 'Nenhuma porta do DNSTT detectada.'
    [[ -f "$SLOWDNS_BUILDINFO" ]] && { printf '\nProveniência da compilação:\n'; sed 's/^/  /' "$SLOWDNS_BUILDINFO"; }
}

rotate_slowdns_keys() {
    require_root
    slowdns_installed || { error 'Instale o SlowDNS primeiro.'; return 1; }
    confirm 'Gerar um novo par de chaves? Os clientes atuais deixarão de conectar.' || return 0
    local backup_dir
    backup_dir="/var/backups/sshplus/slowdns/keys-$(date '+%Y%m%d-%H%M%S')"
    install -d -m 0700 "$backup_dir"
    cp -a "$SLOWDNS_PRIVATE_KEY" "$SLOWDNS_PUBLIC_KEY" "$backup_dir/" 2>/dev/null || true
    rm -f "$SLOWDNS_PRIVATE_KEY" "$SLOWDNS_PUBLIC_KEY"
    slowdns_generate_keys
    systemctl restart "$SLOWDNS_UNIT" 2>/dev/null || true
    slowdns_export_client_info || true
    ok "Novo par de chaves criado. Backup: $backup_dir"
}

remove_slowdns() {
    require_root
    confirm 'Remover os binários e o serviço SlowDNS? Chaves e configuração serão preservadas.' || return
    systemctl disable --now "$SLOWDNS_UNIT" 2>/dev/null || true
    rm -f "$SLOWDNS_SERVER_BINARY" "$SLOWDNS_CLIENT_BINARY"
    rm -rf "$(dirname "$SLOWDNS_BUILDINFO")"
    systemctl daemon-reload
    ok 'SlowDNS removido. Configuração e chaves foram preservadas.'
}

slowdns_menu() {
    local option
    while true; do
        header "SlowDNS / DNSTT ${DNSTT_VERSION}" 'Túnel DNS autenticado com chave pública'
        printf '  1) Instalar ou atualizar\n'
        printf '  2) Configurar domínio, porta e destino\n'
        printf '  3) Exibir status e informações do cliente\n'
        printf '  4) Exportar configuração do cliente\n'
        printf '  5) Iniciar serviço\n'
        printf '  6) Parar serviço\n'
        printf '  7) Reiniciar serviço\n'
        printf '  8) Gerar novas chaves\n'
        printf '  9) Remover SlowDNS\n'
        printf '  0) Voltar\n\n'
        read -r -p 'Opção: ' option
        case "$option" in
            1) install_slowdns; pause ;;
            2) configure_slowdns; pause ;;
            3) show_slowdns_info; pause ;;
            4) slowdns_export_client_info; pause ;;
            5) slowdns_installed && slowdns_validate_config && systemctl enable --now "$SLOWDNS_UNIT" && ok 'SlowDNS iniciado.' || error 'SlowDNS não instalado, não configurado ou não pôde iniciar.'; pause ;;
            6) systemctl stop "$SLOWDNS_UNIT" && ok 'SlowDNS parado.' || error 'Não foi possível parar o serviço.'; pause ;;
            7) slowdns_validate_config && systemctl restart "$SLOWDNS_UNIT" && ok 'SlowDNS reiniciado.' || error 'Não foi possível reiniciar o serviço.'; pause ;;
            8) rotate_slowdns_keys; pause ;;
            9) remove_slowdns; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
