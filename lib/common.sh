#!/usr/bin/env bash
# Funções compartilhadas do SSHPlus Manager.

set -o pipefail
umask 027

export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

SSHPLUS_HOME="${SSHPLUS_HOME:-/opt/sshplus}"
SSHPLUS_CONFIG_DIR="${SSHPLUS_CONFIG_DIR:-/etc/sshplus}"
SSHPLUS_STATE_DIR="${SSHPLUS_STATE_DIR:-/var/lib/sshplus}"
SSHPLUS_LOG_DIR="${SSHPLUS_LOG_DIR:-/var/log/sshplus}"
SSHPLUS_DB="${SSHPLUS_DB:-${SSHPLUS_STATE_DIR}/sshplus.db}"
SSHPLUS_CONF="${SSHPLUS_CONF:-${SSHPLUS_CONFIG_DIR}/sshplus.conf}"
SSHPLUS_LOCK="${SSHPLUS_LOCK:-/run/lock/sshplus.lock}"
SSHPLUS_LEGACY_DB="${SSHPLUS_LEGACY_DB:-${SSHPLUS_STATE_DIR}/users.db}"
SSHPLUS_BACKUP_DIR="${SSHPLUS_BACKUP_DIR:-/var/backups/sshplus}"
SSHPLUS_VERSION_FILE="${SSHPLUS_VERSION_FILE:-${SSHPLUS_HOME}/VERSION}"
SSHPLUS_APT_UPDATED=0

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_CYAN=$'\033[1;36m'
    C_WHITE=$'\033[1;37m'
    C_DIM=$'\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_WHITE=''; C_DIM=''
fi

sshplus_version() {
    local version='desconhecida'
    [[ -r "$SSHPLUS_VERSION_FILE" ]] && version="$(tr -d '\r\n' < "$SSHPLUS_VERSION_FILE")"
    printf '%s\n' "$version"
}


sshplus_ubuntu_version() {
    local version="${SSHPLUS_UBUNTU_VERSION_ID:-}"
    if [[ -z "$version" && -r /etc/os-release ]]; then
        version="$(sed -nE 's/^VERSION_ID="?([^"[:space:]]+)"?.*$/\1/p' /etc/os-release | head -n1)"
    fi
    printf '%s\n' "$version"
}

sshplus_supported_ubuntu() {
    local version="${1:-$(sshplus_ubuntu_version)}"
    [[ "$version" == 24.04 || "$version" == 26.04 ]]
}

sshplus_php_version() {
    local os_version="${1:-$(sshplus_ubuntu_version)}"
    case "$os_version" in
        24.04) printf '8.3\n' ;;
        26.04) printf '8.5\n' ;;
        *) return 1 ;;
    esac
}

sshplus_php_fpm_service() {
    local version
    version="$(sshplus_php_version "${1:-}")" || return 1
    printf 'php%s-fpm.service\n' "$version"
}

sshplus_php_fpm_socket() {
    local version
    version="$(sshplus_php_version "${1:-}")" || return 1
    printf '/run/php/php%s-fpm.sock\n' "$version"
}

sshplus_php_cli_binary() {
    local version
    version="$(sshplus_php_version "${1:-}")" || return 1
    if command -v "php${version}" >/dev/null 2>&1; then
        command -v "php${version}"
    elif command -v php >/dev/null 2>&1; then
        command -v php
    else
        printf 'php%s\n' "$version"
    fi
}

sshplus_php_fpm_binary() {
    local version
    version="$(sshplus_php_version "${1:-}")" || return 1
    if command -v "php-fpm${version}" >/dev/null 2>&1; then
        command -v "php-fpm${version}"
    else
        printf 'php-fpm%s\n' "$version"
    fi
}

log() {
    local level="$1"; shift
    local msg="$*"
    mkdir -p "$SSHPLUS_LOG_DIR" 2>/dev/null || true
    printf '%s [%s] %s\n' "$(date --iso-8601=seconds)" "$level" "$msg" >> "${SSHPLUS_LOG_DIR}/sshplus.log" 2>/dev/null || true
}

info()  { printf '%b[i]%b %s\n' "$C_CYAN" "$C_RESET" "$*"; log INFO "$*"; }
ok()    { printf '%b[+]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; log OK "$*"; }
warn()  { printf '%b[!]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; log WARN "$*"; }
error() { printf '%b[x]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; log ERROR "$*"; }
die()   { error "$*"; exit 1; }

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root: sudo $0"
}

terminal_width() {
    local cols
    cols="$(tput cols 2>/dev/null || printf '80')"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    (( cols < 60 )) && cols=60
    (( cols > 100 )) && cols=100
    printf '%s\n' "$cols"
}

separator() {
    local width="${1:-$(terminal_width)}"
    printf '%*s\n' "$width" '' | tr ' ' '-'
}

header() {
    local title="$1" subtitle="${2:-}"
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then clear 2>/dev/null || true; fi
    printf '%b%s%b\n' "$C_BLUE" "$title" "$C_RESET"
    separator
    [[ -n "$subtitle" ]] && printf '%b%s%b\n\n' "$C_DIM" "$subtitle" "$C_RESET" || printf '\n'
}

pause() {
    [[ -t 0 ]] || return 0
    printf '\n%bPressione ENTER para continuar...%b' "$C_YELLOW" "$C_RESET"
    read -r _ || true
}

confirm() {
    local prompt="${1:-Confirmar?}" answer
    if [[ "${SSHPLUS_ASSUME_YES:-0}" == 1 ]]; then
        return 0
    fi
    [[ -t 0 ]] || return 1
    read -r -p "$prompt [s/N]: " answer
    [[ "$answer" =~ ^[sS]([iI][mM])?$ ]]
}

prompt_value() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " value || return 1
        printf '%s\n' "${value:-$default}"
    else
        read -r -p "$prompt: " value || return 1
        printf '%s\n' "$value"
    fi
}

prompt_secret() {
    local prompt="$1" value
    read -r -s -p "$prompt: " value || return 1
    printf '\n' >&2
    printf '%s\n' "$value"
}

prompt_secret_confirmed() {
    local prompt="${1:-Senha}" first second
    first="$(prompt_secret "$prompt")" || return 1
    second="$(prompt_secret 'Confirme a senha')" || return 1
    [[ "$first" == "$second" ]] || { error 'As senhas não conferem.'; return 1; }
    printf '%s\n' "$first"
}

valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ipv4() {
    local ip="$1" octet
    local -a octets
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
}

valid_hostname() {
    local host="${1,,}" label
    local -a labels
    [[ -n "$host" && ${#host} -le 253 && "$host" != .* && "$host" != *. ]] || return 1
    IFS='.' read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [[ -n "$label" && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
    done
}

valid_endpoint() {
    if [[ "$1" =~ ^[0-9.]+$ ]]; then
        valid_ipv4 "$1"
    else
        valid_hostname "$1"
    fi
}

valid_password() {
    local value="$1"
    [[ ${#value} -ge 8 && "$value" != *:* && "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

valid_date() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$1" '+%F' >/dev/null 2>&1
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

load_env_file() {
    local file="$1" allowed_prefix="${2:-}" line key value
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_whitespace "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || {
            error "Linha de configuração inválida em $file: $line"
            return 1
        }
        key="${BASH_REMATCH[1]}"
        if [[ -n "$allowed_prefix" && "$key" != "$allowed_prefix"* ]]; then
            error "Chave não permitida em $file: $key"
            return 1
        fi
        value="$(trim_whitespace "${BASH_REMATCH[2]}")"
        if [[ ${#value} -ge 2 && "$value" == \"*\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ ${#value} -ge 2 && "$value" == \'*\' ]]; then
            value="${value:1:${#value}-2}"
        fi
        printf -v "$key" '%s' "$value"
    done < "$file"
}

set_config_value() {
    local file="$1" key="$2" value="$3" tmp
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    install -d -m 0750 "$(dirname "$file")"
    tmp="$(mktemp "${file}.XXXXXX")"
    if [[ -f "$file" ]]; then
        awk -v k="$key" -F= '$1 != k {print}' "$file" > "$tmp"
    fi
    value="${value//\"/}"
    printf '%s="%s"\n' "$key" "$value" >> "$tmp"
    chmod 0640 "$tmp"
    mv -f "$tmp" "$file"
}

load_config() {
    SSHPLUS_TIMEZONE=''
    SSHPLUS_SSH_PORT=''
    SSHPLUS_EXPIRE_ACTION=''
    SSHPLUS_GITHUB_REPOSITORY=''
    SSHPLUS_PANEL_LISTEN=''
    SSHPLUS_PANEL_ENABLED=''
    [[ -r "$SSHPLUS_CONF" ]] && load_env_file "$SSHPLUS_CONF" 'SSHPLUS_'
    : "${SSHPLUS_TIMEZONE:=America/Sao_Paulo}"
    : "${SSHPLUS_SSH_PORT:=22}"
    : "${SSHPLUS_EXPIRE_ACTION:=lock}"
    : "${SSHPLUS_GITHUB_REPOSITORY:=}"
    : "${SSHPLUS_PANEL_LISTEN:=127.0.0.1:8088}"
    : "${SSHPLUS_PANEL_ENABLED:=yes}"
    export TZ="$SSHPLUS_TIMEZONE"
}

ensure_runtime_dirs() {
    install -d -m 0750 "$SSHPLUS_CONFIG_DIR" "$SSHPLUS_STATE_DIR" "$SSHPLUS_LOG_DIR" "$SSHPLUS_BACKUP_DIR"
    if declare -F db_init >/dev/null 2>&1; then
        db_init
    fi
}

apt_update_once() {
    (( SSHPLUS_APT_UPDATED == 1 )) && return 0
    info 'Atualizando índices do APT...'
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o Acquire::Retries=3 \
        -o DPkg::Lock::Timeout=120 \
        update
    SSHPLUS_APT_UPDATED=1
}

apt_install() {
    (( $# > 0 )) || return 0
    apt_update_once || return 1
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o Acquire::Retries=3 \
        -o DPkg::Lock::Timeout=120 \
        install -y --no-install-recommends "$@"
}

get_public_ipv4() {
    local ip='' cache="${SSHPLUS_STATE_DIR}/public-ip.cache" now modified
    now="$(date +%s)"
    if [[ -r "$cache" ]]; then
        modified="$(stat -c %Y "$cache" 2>/dev/null || printf 0)"
        if [[ "$modified" =~ ^[0-9]+$ ]] && (( now - modified < 3600 )); then
            ip="$(head -n1 "$cache" 2>/dev/null || true)"
            [[ "$ip" == 'indisponível' ]] || valid_ipv4 "$ip" || ip=''
            [[ -n "$ip" ]] && { printf '%s\n' "$ip"; return; }
        fi
    fi
    if command -v curl >/dev/null 2>&1; then
        ip="$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    fi
    if ! valid_ipv4 "$ip"; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
    fi
    valid_ipv4 "$ip" || ip='indisponível'
    if [[ -d "$SSHPLUS_STATE_DIR" && -w "$SSHPLUS_STATE_DIR" ]]; then
        printf '%s\n' "$ip" > "$cache.tmp" 2>/dev/null && mv -f "$cache.tmp" "$cache" 2>/dev/null || true
        chmod 0600 "$cache" 2>/dev/null || true
    fi
    printf '%s\n' "$ip"
}

service_exists() {
    systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .
}

service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

service_status_text() {
    local unit="$1"
    if ! service_exists "$unit"; then
        printf 'não instalado'
    elif service_active "$unit"; then
        printf 'ativo'
    else
        printf 'inativo'
    fi
}

ssh_unit() {
    service_exists ssh.service && printf 'ssh.service' || printf 'sshd.service'
}

validate_sshd() {
    [[ -x /usr/sbin/sshd ]] && /usr/sbin/sshd -t
}

restart_ssh_safe() {
    local unit
    unit="$(ssh_unit)"
    if validate_sshd; then
        systemctl restart "$unit"
        ok 'OpenSSH reiniciado com configuração válida.'
    else
        error 'A configuração do OpenSSH é inválida; o serviço não foi reiniciado.'
        return 1
    fi
}

format_epoch() {
    local epoch="${1:-0}"
    if [[ "$epoch" == 0 || -z "$epoch" ]]; then
        printf 'sem expiração'
    else
        date -d "@$epoch" '+%d/%m/%Y %H:%M' 2>/dev/null || printf 'inválida'
    fi
}

user_session_pids() {
    local user="$1"
    ps -u "$user" -o pid=,etimes=,comm=,args= 2>/dev/null \
        | awk '$3=="sshd" && $0 ~ /sshd: / {print $1, $2}' \
        | sort -k2,2nr
}

count_user_sessions() {
    user_session_pids "$1" | wc -l
}

managed_user_exists() {
    local user="$1"
    if declare -F db_user_exists >/dev/null 2>&1; then
        db_user_exists "$user"
    else
        return 1
    fi
}

prompt_managed_user() {
    local prompt="${1:-Usuário}" user
    user="$(prompt_value "$prompt")" || return 1
    managed_user_exists "$user" || { error 'Usuário não gerenciado pelo SSHPlus.'; return 1; }
    printf '%s\n' "$user"
}
