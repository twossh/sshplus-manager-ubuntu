#!/usr/bin/env bash
set -euo pipefail
umask 027

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET='/opt/sshplus'; CONF_DIR='/etc/sshplus'; STATE_DIR='/var/lib/sshplus'; LOG_DIR='/var/log/sshplus'
BACKUP_ROOT='/var/backups/sshplus/install'; RELEASE_BACKUP_ROOT='/var/backups/sshplus/releases'
ASSUME_YES=0; SKIP_APT_UPDATE=0; PANEL_ENABLED=1; PANEL_USER='admin'; PANEL_PASSWORD=''; PANEL_LISTEN='127.0.0.1:8088'

usage() {
    cat <<'USAGE'
Uso: sudo ./install.sh [opções]

  -y, --yes                    não solicitar confirmações
      --skip-apt-update        não executar apt-get update
      --no-panel               não habilitar Nginx/PHP-FPM
      --panel-user USUARIO     usuário inicial do painel (padrão: admin)
      --panel-password SENHA   senha inicial; se omitida, será gerada
      --panel-listen ENDERECO  somente loopback, exemplo 127.0.0.1:8088
  -h, --help                   exibir esta ajuda
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --skip-apt-update) SKIP_APT_UPDATE=1 ;;
        --no-panel) PANEL_ENABLED=0 ;;
        --panel-user) shift; PANEL_USER="${1:-}" ;;
        --panel-password) shift; PANEL_PASSWORD="${1:-}" ;;
        --panel-listen) shift; PANEL_LISTEN="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Opção desconhecida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

export SSHPLUS_ASSUME_YES="$ASSUME_YES" SSHPLUS_HOME="$BASE_DIR"
source "$BASE_DIR/lib/common.sh"
require_root
[[ -d /run/systemd/system ]] || die 'Este instalador requer systemd.'
[[ -r /etc/os-release ]] || die 'Sistema operacional não identificado.'
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die 'Este instalador é exclusivo para Ubuntu.'
sshplus_supported_ubuntu "${VERSION_ID:-}" || die "Versão não suportada: ${PRETTY_NAME:-desconhecido}. Use Ubuntu 24.04 LTS ou 26.04 LTS."
export SSHPLUS_UBUNTU_VERSION_ID="${VERSION_ID:-}"
PHP_VERSION="$(sshplus_php_version "${VERSION_ID:-}")"
PHP_FPM_SERVICE="$(sshplus_php_fpm_service "${VERSION_ID:-}")"
PHP_FPM_SOCKET="$(sshplus_php_fpm_socket "${VERSION_ID:-}")"
PHP_CLI_BINARY="php${PHP_VERSION}"
valid_username "$PANEL_USER" || die 'Usuário inicial do painel inválido.'
[[ "$PANEL_LISTEN" =~ ^127\.0\.0\.1:([0-9]{1,5})$ || "$PANEL_LISTEN" =~ ^\[::1\]:([0-9]{1,5})$ ]] || die 'O painel deve escutar apenas em loopback.'
panel_port="${BASH_REMATCH[1]}"; valid_port "$panel_port" || die 'Porta do painel inválida.'
[[ -z "$PANEL_PASSWORD" ]] || valid_password "$PANEL_PASSWORD" || die 'A senha do painel precisa ter no mínimo 8 caracteres.'

header "SSHPlus Manager $(tr -d '\r\n' < "$BASE_DIR/VERSION")" "Plataforma modular para Ubuntu ${VERSION_ID} LTS — PHP ${PHP_VERSION}"
(( SKIP_APT_UPDATE == 1 )) && SSHPLUS_APT_UPDATED=1
packages=(openssh-server curl jq bc procps iproute2 util-linux tar gzip ca-certificates ufw fail2ban logrotate sqlite3 sudo openssl iputils-ping)
if (( PANEL_ENABLED == 1 )); then packages+=(nginx "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli"); fi
apt_install "${packages[@]}"

stamp="$(date '+%Y%m%d-%H%M%S')"; backup_dir="$BACKUP_ROOT/$stamp"
install -d -m 0700 "$backup_dir" "$RELEASE_BACKUP_ROOT"
backup_path() { local path="$1"; [[ -e "$path" || -L "$path" ]] && cp -a --parents "$path" "$backup_dir/" || true; }
for path in /etc/ssh/sshd_config.d/00-sshplus.conf /etc/ssh/sshd_config.d/90-sshplus.conf "$CONF_DIR" "$STATE_DIR" \
  /etc/fail2ban/jail.d/sshplus.local /etc/logrotate.d/sshplus /etc/tmpfiles.d/sshplus.conf \
  /etc/nginx/sites-available/sshplus-panel /etc/nginx/sites-enabled/sshplus-panel /etc/sudoers.d/sshplus-api; do backup_path "$path"; done

if [[ -d "$TARGET" && -r "$TARGET/VERSION" ]]; then
    old_version="$(tr -d '\r\n' < "$TARGET/VERSION")"
    release_snapshot="$RELEASE_BACKUP_ROOT/sshplus-release-${stamp}-v${old_version}-before-install.tar.gz"
    tar --numeric-owner -C / -czf "$release_snapshot" "${TARGET#/}"
    chmod 0600 "$release_snapshot"
fi

info 'Instalando a aplicação de forma atômica...'
rm -rf "$TARGET.new"; install -d -m 0755 "$TARGET.new"
for dir in bin lib modules api web database nginx sudoers; do cp -a "$BASE_DIR/$dir" "$TARGET.new/"; done
for file in REPOSITORY VERSION TARGET; do install -m 0644 "$BASE_DIR/$file" "$TARGET.new/$file"; done
find "$TARGET.new/bin" -type f -exec chmod 0755 {} +
find "$TARGET.new/lib" "$TARGET.new/modules" -type f -exec chmod 0644 {} +
find "$TARGET.new/api" "$TARGET.new/web" "$TARGET.new/database" "$TARGET.new/nginx" "$TARGET.new/sudoers" -type f -exec chmod 0644 {} +
rm -rf "$TARGET.old"; had_previous=0
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$TARGET.old"; had_previous=1; fi
if ! mv "$TARGET.new" "$TARGET"; then
    rm -rf "$TARGET"; (( had_previous == 1 )) && mv "$TARGET.old" "$TARGET"; die 'Falha ao ativar a nova versão; a anterior foi restaurada.'
fi

getent group sshplus-api >/dev/null 2>&1 || groupadd --system sshplus-api
if (( PANEL_ENABLED == 1 )); then
    id www-data >/dev/null 2>&1 || die 'Usuário www-data não encontrado após instalar Nginx/PHP.'
    usermod -a -G sshplus-api www-data
fi
install -d -m 0750 -o root -g sshplus-api "$CONF_DIR"
install -d -m 0750 -o root -g root "$STATE_DIR"
install -d -m 0750 -o root -g adm "$LOG_DIR"

DETECTED_SSH_PORT="$(/usr/sbin/sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"; DETECTED_SSH_PORT="${DETECTED_SSH_PORT:-22}"
if [[ ! -f "$CONF_DIR/sshplus.conf" ]]; then
    cat > "$CONF_DIR/sshplus.conf" <<CONF
SSHPLUS_TIMEZONE="America/Sao_Paulo"
SSHPLUS_SSH_PORT="$DETECTED_SSH_PORT"
SSHPLUS_EXPIRE_ACTION="lock"
SSHPLUS_GITHUB_REPOSITORY=""
SSHPLUS_PANEL_ENABLED="$([[ $PANEL_ENABLED == 1 ]] && echo yes || echo no)"
SSHPLUS_PANEL_LISTEN="$PANEL_LISTEN"
CONF
else
    set_config_value "$CONF_DIR/sshplus.conf" SSHPLUS_PANEL_ENABLED "$([[ $PANEL_ENABLED == 1 ]] && echo yes || echo no)"
    set_config_value "$CONF_DIR/sshplus.conf" SSHPLUS_PANEL_LISTEN "$PANEL_LISTEN"
fi
chmod 0640 "$CONF_DIR/sshplus.conf"
BUNDLED_REPOSITORY="$(tr -d '\r\n[:space:]' < "$BASE_DIR/REPOSITORY" 2>/dev/null || true)"
if [[ "$BUNDLED_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$BUNDLED_REPOSITORY" != SEU_USUARIO/* ]]; then
    grep -q '^SSHPLUS_GITHUB_REPOSITORY="[^" ]\+"' "$CONF_DIR/sshplus.conf" 2>/dev/null || set_config_value "$CONF_DIR/sshplus.conf" SSHPLUS_GITHUB_REPOSITORY "$BUNDLED_REPOSITORY"
fi

touch "$LOG_DIR/sshplus.log" "$LOG_DIR/operations.log" "$LOG_DIR/panel-access.log" "$LOG_DIR/panel-error.log"
chown root:adm "$LOG_DIR"/*.log; chmod 0640 "$LOG_DIR"/*.log

cat > /etc/tmpfiles.d/sshplus.conf <<'CONF'
d /etc/sshplus 0750 root sshplus-api -
d /var/lib/sshplus 0750 root root -
d /var/log/sshplus 0750 root adm -
f /var/log/sshplus/sshplus.log 0640 root adm -
f /var/log/sshplus/operations.log 0640 root adm -
f /var/log/sshplus/panel-access.log 0640 root adm -
f /var/log/sshplus/panel-error.log 0640 root adm -
CONF
systemd-tmpfiles --create /etc/tmpfiles.d/sshplus.conf
cat > /etc/logrotate.d/sshplus <<'CONF'
/var/log/sshplus/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        systemctl reload nginx.service >/dev/null 2>&1 || true
    endscript
}
CONF
chmod 0644 /etc/logrotate.d/sshplus

export SSHPLUS_HOME="$TARGET" SSHPLUS_CONFIG_DIR="$CONF_DIR" SSHPLUS_STATE_DIR="$STATE_DIR" SSHPLUS_LOG_DIR="$LOG_DIR" SSHPLUS_DB="$STATE_DIR/sshplus.db"
source "$TARGET/lib/database.sh"
db_init
[[ -f "$STATE_DIR/users.db" ]] && db_migrate_legacy "$STATE_DIR/users.db"
[[ -f /root/usuarios.db ]] && db_migrate_legacy /root/usuarios.db
chown root:root "$STATE_DIR/sshplus.db"; chmod 0600 "$STATE_DIR/sshplus.db"

credentials_created=0
auth_file="$CONF_DIR/panel-auth.json"
if (( PANEL_ENABLED == 1 )); then
    if [[ -s "$auth_file" ]] && ! jq -e '.version == 1 and (.accounts | type == "array" and length > 0) and all(.accounts[]; (.username | type == "string") and (.password_hash | type == "string") and (.role | IN("admin","operator","viewer")) and (.active | type == "boolean"))' "$auth_file" >/dev/null 2>&1; then
        mv "$auth_file" "${auth_file}.invalid-${stamp}"
        warn 'Arquivo de autenticação inválido preservado; ele será reconstruído pelo banco administrativo.'
    fi
    if [[ ! -s "$auth_file" ]]; then
        api_count="$(db_query 'SELECT count(*) FROM api_users;')"
        if [[ "$api_count" =~ ^[1-9][0-9]*$ ]]; then
            account_rows="$(db_query_json 'SELECT username,password_hash,role,active FROM api_users ORDER BY id;')"
            printf '%s' "$account_rows" | jq '{version:1,accounts:map({username:.username,password_hash:.password_hash,role:.role,active:(.active == 1)})}' > "$auth_file.tmp"
            install -m 0640 -o root -g sshplus-api "$auth_file.tmp" "$auth_file"
            rm -f "$auth_file.tmp"
        else
            if [[ -z "$PANEL_PASSWORD" ]]; then PANEL_PASSWORD="$(openssl rand -hex 16)"; fi
            password_hash="$("$PHP_CLI_BINARY" -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$PANEL_PASSWORD")"
            db_api_user_upsert "$PANEL_USER" "$password_hash" admin
            jq -n --arg username "$PANEL_USER" --arg password_hash "$password_hash" \
                '{version:1,accounts:[{username:$username,password_hash:$password_hash,role:"admin",active:true}]}' > "$auth_file.tmp"
            install -m 0640 -o root -g sshplus-api "$auth_file.tmp" "$auth_file"
            rm -f "$auth_file.tmp"
            credentials_created=1
            cat > /root/sshplus-panel-credentials.txt <<CRED
SSHPlus Manager $(tr -d '\r\n' < "$BASE_DIR/VERSION")
Usuário: $PANEL_USER
Senha: $PANEL_PASSWORD
Acesso local: http://127.0.0.1:$panel_port
Túnel SSH: ssh -L $panel_port:127.0.0.1:$panel_port usuario@IP_DA_VPS
CRED
            chmod 0600 /root/sshplus-panel-credentials.txt
            audit_log installer install panel.account "$PANEL_USER" 1
        fi
    fi
    chown root:sshplus-api "$auth_file"
    chmod 0640 "$auth_file"
fi

install -d -m 0755 /etc/ssh/sshd_config.d
rm -f /etc/ssh/sshd_config.d/90-sshplus.conf
install -m 0644 "$BASE_DIR/config/00-sshplus.conf" /etc/ssh/sshd_config.d/00-sshplus.conf
for unit in "$BASE_DIR"/systemd/*; do install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"; done
ln -sfn "$TARGET/bin/sshplus" /usr/local/sbin/sshplus; ln -sfn "$TARGET/bin/sshplus" /usr/local/bin/menu
ln -sfn "$TARGET/bin/sshplus-badvpn" /usr/local/sbin/sshplus-badvpn; ln -sfn "$TARGET/bin/sshplus-badvpn" /usr/local/sbin/badvpn
ln -sfn "$TARGET/bin/sshplus-slowdns" /usr/local/sbin/sshplus-slowdns; ln -sfn "$TARGET/bin/sshplus-slowdns" /usr/local/sbin/slowdns
ln -sfn "$TARGET/bin/sshplus-agent" /usr/local/sbin/sshplus-agent
ln -sfn "$TARGET/bin/sshplus-healthcheck" /usr/local/sbin/sshplus-healthcheck

if (( PANEL_ENABLED == 1 )); then
    install -m 0440 "$BASE_DIR/sudoers/sshplus-api" /etc/sudoers.d/sshplus-api
    visudo -cf /etc/sudoers.d/sshplus-api >/dev/null || die 'Configuração sudoers inválida.'
    sed -e "s|@PANEL_LISTEN@|$PANEL_LISTEN|g" -e "s|@PHP_FPM_SOCKET@|$PHP_FPM_SOCKET|g" \
        "$BASE_DIR/nginx/sshplus-panel.conf.template" > /etc/nginx/sites-available/sshplus-panel
    ln -sfn /etc/nginx/sites-available/sshplus-panel /etc/nginx/sites-enabled/sshplus-panel
    rm -f /etc/nginx/sites-enabled/default
    install -d -m 0755 "/etc/php/${PHP_VERSION}/fpm/conf.d"
    cat > "/etc/php/${PHP_VERSION}/fpm/conf.d/99-sshplus.ini" <<'PHPINI'
expose_php=Off
session.cookie_httponly=1
session.cookie_samesite=Strict
session.use_strict_mode=1
session.gc_maxlifetime=3600
memory_limit=128M
max_execution_time=600
post_max_size=128K
upload_max_filesize=128K
PHPINI
    nginx -t
fi

if ! /usr/sbin/sshd -t; then
    rm -f /etc/ssh/sshd_config.d/00-sshplus.conf /etc/ssh/sshd_config.d/90-sshplus.conf
    [[ -f "$backup_dir/etc/ssh/sshd_config.d/00-sshplus.conf" ]] && install -m 0644 "$backup_dir/etc/ssh/sshd_config.d/00-sshplus.conf" /etc/ssh/sshd_config.d/00-sshplus.conf
    [[ -f "$backup_dir/etc/ssh/sshd_config.d/90-sshplus.conf" ]] && install -m 0644 "$backup_dir/etc/ssh/sshd_config.d/90-sshplus.conf" /etc/ssh/sshd_config.d/90-sshplus.conf
    die 'OpenSSH inválido; configuração anterior restaurada.'
fi

systemctl daemon-reload
systemctl enable --now sshplus-expirer.timer sshplus-limiter.timer sshplus-metrics.timer
systemctl restart "$(ssh_unit)"
if (( PANEL_ENABLED == 1 )); then systemctl enable --now "$PHP_FPM_SERVICE" nginx.service; systemctl restart "$PHP_FPM_SERVICE" nginx.service; fi

install -d -m 0755 /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshplus.local <<CONF
[sshd]
enabled = true
port = $DETECTED_SSH_PORT
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
CONF
systemctl enable --now fail2ban.service; systemctl restart fail2ban.service
command -v ufw >/dev/null 2>&1 && ufw allow "${DETECTED_SSH_PORT}/tcp" comment 'SSHPlus OpenSSH' >/dev/null || true
rm -rf "$TARGET.old"

printf '\n'; ok "SSHPlus Manager $(sshplus_version) instalado."
printf '  CLI:               sudo menu\n'
printf '  Banco SQLite:      %s\n' "$STATE_DIR/sshplus.db"
printf '  Backup anterior:   %s\n' "$backup_dir"
if (( PANEL_ENABLED == 1 )); then
    printf '  Painel local:       http://127.0.0.1:%s\n' "$panel_port"
    printf '  Túnel SSH:          ssh -L %s:127.0.0.1:%s usuario@IP_DA_VPS\n' "$panel_port" "$panel_port"
    (( credentials_created == 1 )) && printf '  Credencial inicial: /root/sshplus-panel-credentials.txt\n'
fi
printf '\nA autenticação root por senha não foi habilitada. O painel não foi exposto à internet.\n'
