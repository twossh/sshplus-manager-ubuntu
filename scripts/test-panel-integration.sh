#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${SSHPLUS_TEST_PANEL_PORT:-18088}"
PASSWORD='TesteSeguro123'
SERVER_PID=''

cleanup() {
    set +e
    [[ -n "$SERVER_PID" ]] && sudo kill "$SERVER_PID" >/dev/null 2>&1 || true
    sudo rm -rf /opt/sshplus /etc/sshplus /var/lib/sshplus /var/log/sshplus /var/backups/sshplus
    sudo rm -f /etc/sudoers.d/sshplus-api /tmp/sshplus-test-* /tmp/panel-cookies
    sudo gpasswd -d www-data sshplus-api >/dev/null 2>&1 || true
    sudo groupdel sshplus-api >/dev/null 2>&1 || true
}
trap cleanup EXIT

[[ -r /etc/os-release ]] || { echo 'Sistema não identificado.' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && ( "${VERSION_ID:-}" == 24.04 || "${VERSION_ID:-}" == 26.04 ) ]] || {
    echo "Teste de painel ignorado fora do Ubuntu 24.04/26.04: ${PRETTY_NAME:-desconhecido}"
    exit 0
}

command -v php >/dev/null
command -v jq >/dev/null
command -v sqlite3 >/dev/null
command -v sudo >/dev/null
id www-data >/dev/null

sudo cp -a "$ROOT" /opt/sshplus
sudo find /opt/sshplus/bin -type f -exec chmod 0755 {} +
sudo groupadd --system sshplus-api 2>/dev/null || true
sudo usermod -a -G sshplus-api www-data
sudo install -d -m 0750 -o root -g sshplus-api /etc/sshplus
sudo install -d -m 0750 -o root -g root /var/lib/sshplus /var/backups/sshplus
sudo install -d -m 0750 -o root -g adm /var/log/sshplus
sudo install -m 0440 /opt/sshplus/sudoers/sshplus-api /etc/sudoers.d/sshplus-api
sudo visudo -cf /etc/sudoers.d/sshplus-api >/dev/null
sudo tee /etc/sshplus/sshplus.conf >/dev/null <<CONF
SSHPLUS_TIMEZONE="America/Sao_Paulo"
SSHPLUS_PANEL_LISTEN="127.0.0.1:$PORT"
SSHPLUS_PANEL_ENABLED="yes"
CONF
sudo chmod 0640 /etc/sshplus/sshplus.conf

sudo env SSHPLUS_HOME=/opt/sshplus SSHPLUS_STATE_DIR=/var/lib/sshplus SSHPLUS_DB=/var/lib/sshplus/sshplus.db \
    SSHPLUS_CONFIG_DIR=/etc/sshplus SSHPLUS_LOG_DIR=/var/log/sshplus bash -c \
    'source /opt/sshplus/lib/common.sh; source /opt/sshplus/lib/database.sh; db_init'
hash="$(php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$PASSWORD")"
sudo env SSHPLUS_HOME=/opt/sshplus SSHPLUS_STATE_DIR=/var/lib/sshplus SSHPLUS_DB=/var/lib/sshplus/sshplus.db \
    SSHPLUS_CONFIG_DIR=/etc/sshplus SSHPLUS_LOG_DIR=/var/log/sshplus HASH="$hash" bash -c \
    'source /opt/sshplus/lib/common.sh; source /opt/sshplus/lib/database.sh; db_api_user_upsert admin "$HASH" admin'
jq -n --arg hash "$hash" '{version:1,accounts:[{username:"admin",password_hash:$hash,role:"admin",active:true}]}' >/tmp/sshplus-test-auth
sudo install -m 0640 -o root -g sshplus-api /tmp/sshplus-test-auth /etc/sshplus/panel-auth.json
sudo touch /var/log/sshplus/php-error.log
sudo chown root:sshplus-api /var/log/sshplus/php-error.log
sudo chmod 0660 /var/log/sshplus/php-error.log

sudo -u www-data php -S "127.0.0.1:$PORT" -t /opt/sshplus/web/public >/tmp/sshplus-test-server.log 2>&1 &
SERVER_PID=$!
sleep 1

# O login deve continuar correto mesmo se o agente estiver temporariamente indisponível.
sudo mv /etc/sudoers.d/sshplus-api /etc/sudoers.d/sshplus-api.disabled
invalid_code="$(curl -sS -o /tmp/sshplus-test-invalid.json -w '%{http_code}' -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"errada"}' "http://127.0.0.1:$PORT/api/login")"
[[ "$invalid_code" == 401 ]]
valid_code="$(curl -sS -o /tmp/sshplus-test-login-no-agent.json -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"$PASSWORD\"}" "http://127.0.0.1:$PORT/api/login")"
[[ "$valid_code" == 200 ]]
jq -e '.ok == true' /tmp/sshplus-test-login-no-agent.json >/dev/null
sudo mv /etc/sudoers.d/sshplus-api.disabled /etc/sudoers.d/sshplus-api

printf '{}\n' | sudo -u www-data sudo -n -- /opt/sshplus/bin/sshplus-agent health | jq -e '.ok == true' >/dev/null
curl -fsS "http://127.0.0.1:$PORT/api/health" | jq -e \
    '.ok == true and .checks.session == true and .checks.auth_readable == true and .checks.auth_accounts == 1 and .checks.agent == true' >/dev/null

login_code="$(curl -sS -o /tmp/sshplus-test-login.json -w '%{http_code}' -c /tmp/panel-cookies \
    -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$PASSWORD\"}" \
    "http://127.0.0.1:$PORT/api/login")"
[[ "$login_code" == 200 ]]
curl -fsS -b /tmp/panel-cookies "http://127.0.0.1:$PORT/api/status" | jq -e '.ok == true' >/dev/null

echo 'Teste integrado do painel aprovado.'
