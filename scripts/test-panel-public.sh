#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/nginx/sshplus-panel-public.conf.template"
TMP="$(mktemp -d /tmp/sshplus-public-panel-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$TEMPLATE" ]]
for token in DOMAIN ACME_ROOT FULLCHAIN PRIVKEY PHP_FPM_SOCKET; do
    grep -q "@$token@" "$TEMPLATE" || {
        printf 'Placeholder ausente no template público: @%s@\n' "$token" >&2
        exit 1
    }
done

command -v openssl >/dev/null 2>&1 || {
    printf 'OpenSSL ausente para teste do painel público.\n' >&2
    exit 1
}
command -v nginx >/dev/null 2>&1 || {
    printf 'Nginx ausente para teste do painel público.\n' >&2
    exit 1
}

mkdir -p "$TMP/acme" "$TMP/log" "$TMP/run" "$TMP/web"
cp /etc/nginx/fastcgi.conf "$TMP/fastcgi.conf"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=panel.example.test' \
    -keyout "$TMP/privkey.pem" -out "$TMP/fullchain.pem" >/dev/null 2>&1

sed \
    -e 's|@DOMAIN@|panel.example.test|g' \
    -e "s|@ACME_ROOT@|$TMP/acme|g" \
    -e "s|@FULLCHAIN@|$TMP/fullchain.pem|g" \
    -e "s|@PRIVKEY@|$TMP/privkey.pem|g" \
    -e "s|@PHP_FPM_SOCKET@|$TMP/run/php-fpm.sock|g" \
    -e "s|/var/log/sshplus|$TMP/log|g" \
    -e "s|/opt/sshplus/web/public|$TMP/web|g" \
    "$TEMPLATE" > "$TMP/panel-public.conf"

if grep -Eq '@(DOMAIN|ACME_ROOT|FULLCHAIN|PRIVKEY|PHP_FPM_SOCKET)@' "$TMP/panel-public.conf"; then
    printf 'Template público ainda contém placeholders.\n' >&2
    exit 1
fi

cat > "$TMP/nginx.conf" <<NGINX
worker_processes 1;
error_log $TMP/log/nginx-error.log;
pid $TMP/run/nginx.pid;
events { worker_connections 32; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log $TMP/log/nginx-access.log;
    limit_req_zone \$binary_remote_addr zone=sshplus_login:10m rate=5r/m;
    include $TMP/panel-public.conf;
}
NGINX

nginx -t -p "$TMP/" -c "$TMP/nginx.conf" >/dev/null
grep -q 'listen 443 ssl http2;' "$TMP/panel-public.conf"
grep -q 'Strict-Transport-Security' "$TMP/panel-public.conf"
grep -q 'fastcgi_param HTTPS on;' "$TMP/panel-public.conf"

echo 'Template do painel público HTTPS aprovado.'
