#!/usr/bin/env bash

BADVPN_VERSION='1.999.130'
BADVPN_REPO='https://github.com/ambrop72/badvpn.git'
BADVPN_COMMIT_PREFIX='752c6b4'
BADVPN_BINARY='/usr/local/sbin/badvpn-udpgw'
BADVPN_UNIT='sshplus-badvpn.service'
BADVPN_ENV='/etc/sshplus/badvpn.env'
BADVPN_LICENSE_DIR='/usr/local/share/licenses/sshplus-badvpn'

badvpn_installed() {
    [[ -x "$BADVPN_BINARY" ]] && "$BADVPN_BINARY" --version 2>&1 | grep -q "${BADVPN_VERSION}"
}

badvpn_version_text() {
    if [[ -x "$BADVPN_BINARY" ]]; then
        "$BADVPN_BINARY" --version 2>&1 | head -n 1
    else
        printf 'não instalado\n'
    fi
}

badvpn_write_default_config() {
    install -d -m 0750 /etc/sshplus
    [[ -f "$BADVPN_ENV" ]] && return 0
    cat > "$BADVPN_ENV" <<'CONF'
BADVPN_LISTEN_ADDR=127.0.0.1:7300
BADVPN_MAX_CLIENTS=1000
BADVPN_MAX_CONNECTIONS_PER_CLIENT=10
BADVPN_CLIENT_SNDBUF=1048576
BADVPN_LOGLEVEL=notice
CONF
    chmod 0640 "$BADVPN_ENV"
}

badvpn_validate_config() {
    local config_file="${1:-$BADVPN_ENV}" listen max_clients max_conn sndbuf loglevel host port
    BADVPN_LISTEN_ADDR=''; BADVPN_MAX_CLIENTS=''; BADVPN_MAX_CONNECTIONS_PER_CLIENT=''
    BADVPN_CLIENT_SNDBUF=''; BADVPN_LOGLEVEL=''
    [[ -r "$config_file" ]] || { error "Configuração ausente: $config_file"; return 1; }
    load_env_file "$config_file" 'BADVPN_' || return 1
    listen="${BADVPN_LISTEN_ADDR:-}"
    max_clients="${BADVPN_MAX_CLIENTS:-}"
    max_conn="${BADVPN_MAX_CONNECTIONS_PER_CLIENT:-}"
    sndbuf="${BADVPN_CLIENT_SNDBUF:-}"
    loglevel="${BADVPN_LOGLEVEL:-}"

    if [[ "$listen" =~ ^127\.0\.0\.1:([0-9]{1,5})$ ]]; then
        host='127.0.0.1'; port="${BASH_REMATCH[1]}"
    elif [[ "$listen" =~ ^\[::1\]:([0-9]{1,5})$ ]]; then
        host='::1'; port="${BASH_REMATCH[1]}"
    else
        error 'O BadVPN deve escutar apenas em 127.0.0.1 ou [::1].'
        return 1
    fi
    (( 10#$port >= 1 && 10#$port <= 65535 )) || { error 'Porta BadVPN inválida.'; return 1; }
    [[ "$max_clients" =~ ^[1-9][0-9]*$ ]] && (( 10#$max_clients <= 100000 )) || { error 'BADVPN_MAX_CLIENTS inválido.'; return 1; }
    [[ "$max_conn" =~ ^[1-9][0-9]*$ ]] && (( 10#$max_conn <= 10000 )) || { error 'BADVPN_MAX_CONNECTIONS_PER_CLIENT inválido.'; return 1; }
    [[ "$sndbuf" =~ ^[0-9]+$ ]] && (( 10#$sndbuf <= 16777216 )) || { error 'BADVPN_CLIENT_SNDBUF inválido.'; return 1; }
    [[ "$loglevel" =~ ^(none|error|warning|notice|info|debug|[0-5])$ ]] || { error 'BADVPN_LOGLEVEL inválido.'; return 1; }
    : "$host"
}

install_badvpn() (
    require_root
    local work src build commit version_output backup_dir
    info "Preparando BadVPN UDPGW ${BADVPN_VERSION} a partir do repositório oficial arquivado."
    apt_install build-essential cmake git ca-certificates || {
        error 'Não foi possível instalar as dependências de compilação.'
        return 1
    }

    work="$(mktemp -d /tmp/sshplus-badvpn.XXXXXX)"
    trap 'rm -rf "${work:-}"' EXIT INT TERM
    src="$work/source"
    build="$work/build"

    GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --branch "$BADVPN_VERSION" "$BADVPN_REPO" "$src" || {
        error 'Falha ao obter o código-fonte oficial do BadVPN no GitHub.'
        return 1
    }
    commit="$(git -C "$src" rev-parse --short=7 HEAD)"
    [[ "$commit" == "$BADVPN_COMMIT_PREFIX" ]] || {
        error "O código recebido não corresponde ao release esperado (${BADVPN_COMMIT_PREFIX}); recebido ${commit}."
        return 1
    }

    cmake -S "$src" -B "$build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_NOTHING_BY_DEFAULT=1 \
        -DBUILD_UDPGW=1 || {
            error 'Falha na configuração do código-fonte com CMake.'
            return 1
        }
    cmake --build "$build" --parallel "$(nproc)" || {
        error 'Falha ao compilar o BadVPN UDPGW.'
        return 1
    }
    [[ -x "$build/udpgw/badvpn-udpgw" ]] || { error 'Binário compilado não foi encontrado.'; return 1; }
    version_output="$($build/udpgw/badvpn-udpgw --version 2>&1 | head -n 1)"
    [[ "$version_output" == *"$BADVPN_VERSION"* ]] || {
        error "A compilação retornou uma versão inesperada: $version_output"
        return 1
    }

    backup_dir="/var/backups/sshplus/badvpn/$(date '+%Y%m%d-%H%M%S')"
    install -d -m 0700 "$backup_dir"
    [[ -e "$BADVPN_BINARY" ]] && cp -a "$BADVPN_BINARY" "$backup_dir/" || true
    [[ -e /bin/badvpn-udpgw ]] && cp -a /bin/badvpn-udpgw "$backup_dir/badvpn-udpgw.legacy" || true

    install -m 0755 "$build/udpgw/badvpn-udpgw" "$BADVPN_BINARY"
    ln -sfn "$BADVPN_BINARY" /usr/local/bin/badvpn-udpgw
    command -v strip >/dev/null 2>&1 && strip --strip-unneeded "$BADVPN_BINARY" 2>/dev/null || true
    install -d -m 0755 "$BADVPN_LICENSE_DIR"
    install -m 0644 "$src/COPYING" "$BADVPN_LICENSE_DIR/COPYING"
    badvpn_write_default_config
    badvpn_validate_config || return 1

    systemctl daemon-reload
    systemctl enable --now "$BADVPN_UNIT" || {
        error 'O BadVPN foi compilado, mas o serviço não iniciou.'
        systemctl --no-pager --full status "$BADVPN_UNIT" || true
        return 1
    }
    ok "BadVPN UDPGW ${BADVPN_VERSION} instalado e ativo em loopback."
    info "Backup do binário anterior: $backup_dir"
)

configure_badvpn() {
    require_root
    local current_listen current_clients current_conn current_buf current_log
    local listen clients conn buf loglevel
    badvpn_write_default_config
    load_env_file "$BADVPN_ENV" 'BADVPN_' || return 1
    current_listen="${BADVPN_LISTEN_ADDR:-127.0.0.1:7300}"
    current_clients="${BADVPN_MAX_CLIENTS:-1000}"
    current_conn="${BADVPN_MAX_CONNECTIONS_PER_CLIENT:-10}"
    current_buf="${BADVPN_CLIENT_SNDBUF:-1048576}"
    current_log="${BADVPN_LOGLEVEL:-notice}"

    read -r -p "Endereço local e porta [$current_listen]: " listen; listen="${listen:-$current_listen}"
    read -r -p "Máximo de clientes [$current_clients]: " clients; clients="${clients:-$current_clients}"
    read -r -p "Conexões por cliente [$current_conn]: " conn; conn="${conn:-$current_conn}"
    read -r -p "Buffer de envio em bytes [$current_buf]: " buf; buf="${buf:-$current_buf}"
    read -r -p "Log none/error/warning/notice/info/debug [$current_log]: " loglevel; loglevel="${loglevel:-$current_log}"

    local temp
    temp="$(mktemp "${BADVPN_ENV}.XXXXXX")"
    cat > "$temp" <<CONF
BADVPN_LISTEN_ADDR=$listen
BADVPN_MAX_CLIENTS=$clients
BADVPN_MAX_CONNECTIONS_PER_CLIENT=$conn
BADVPN_CLIENT_SNDBUF=$buf
BADVPN_LOGLEVEL=$loglevel
CONF
    chmod 0640 "$temp"
    if ! badvpn_validate_config "$temp"; then
        rm -f "$temp"
        error 'Configuração rejeitada; o arquivo anterior foi preservado.'
        return 1
    fi
    mv -f "$temp" "$BADVPN_ENV"
    if badvpn_installed; then
        systemctl restart "$BADVPN_UNIT" && ok 'Configuração aplicada.'
    else
        ok 'Configuração salva; instale o BadVPN para ativá-la.'
    fi
}

show_badvpn_status() {
    header 'BadVPN UDPGW'
    printf 'Versão esperada: %s\n' "$BADVPN_VERSION"
    printf 'Versão instalada: %s\n' "$(badvpn_version_text)"
    printf 'Serviço: %s\n\n' "$(service_status_text "$BADVPN_UNIT")"
    [[ -r "$BADVPN_ENV" ]] && { echo 'Configuração:'; sed 's/^/  /' "$BADVPN_ENV"; echo; }
    systemctl --no-pager --full status "$BADVPN_UNIT" 2>/dev/null || true
    printf '\nPorta em escuta:\n'
    ss -lntp 2>/dev/null | grep -F 'badvpn-udpgw' || echo 'Nenhuma porta BadVPN detectada.'
}

remove_badvpn() {
    require_root
    confirm 'Remover o BadVPN UDPGW e seu serviço?' || return
    systemctl disable --now "$BADVPN_UNIT" 2>/dev/null || true
    rm -f "$BADVPN_BINARY" /usr/local/bin/badvpn-udpgw
    rm -rf "$BADVPN_LICENSE_DIR"
    systemctl daemon-reload
    ok 'BadVPN removido. A configuração foi preservada em /etc/sshplus/badvpn.env.'
}

badvpn_menu() {
    local option
    while true; do
        header "BadVPN UDPGW ${BADVPN_VERSION}" 'Serviço local em loopback'
        printf '  1) Instalar ou atualizar\n'
        printf '  2) Configurar\n'
        printf '  3) Exibir status\n'
        printf '  4) Iniciar serviço\n'
        printf '  5) Parar serviço\n'
        printf '  6) Reiniciar serviço\n'
        printf '  7) Remover BadVPN\n'
        printf '  0) Voltar\n\n'
        read -r -p 'Opção: ' option
        case "$option" in
            1) install_badvpn; pause ;;
            2) configure_badvpn; pause ;;
            3) show_badvpn_status; pause ;;
            4) badvpn_installed && systemctl enable --now "$BADVPN_UNIT" && ok 'BadVPN iniciado.' || error 'BadVPN não instalado ou não pôde ser iniciado.'; pause ;;
            5) systemctl stop "$BADVPN_UNIT" && ok 'BadVPN parado.' || error 'Não foi possível parar o serviço.'; pause ;;
            6) badvpn_validate_config && systemctl restart "$BADVPN_UNIT" && ok 'BadVPN reiniciado.' || error 'Não foi possível reiniciar o serviço.'; pause ;;
            7) remove_badvpn; pause ;;
            0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
