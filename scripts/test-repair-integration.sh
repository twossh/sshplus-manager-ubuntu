#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/sshplus-repair-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/os-release" <<'OS'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS (teste)"
OS

mkdir -p "$TMP/etc" "$TMP/state" "$TMP/log" "$TMP/backups" "$TMP/systemd" \
    "$TMP/local-sbin" "$TMP/local-bin" "$TMP/sshd" "$TMP/tmpfiles" "$TMP/logrotate"

run_repair() {
    SSHPLUS_HOME="$ROOT" \
    SSHPLUS_CONFIG_DIR="$TMP/etc" \
    SSHPLUS_STATE_DIR="$TMP/state" \
    SSHPLUS_LOG_DIR="$TMP/log" \
    SSHPLUS_BACKUP_DIR="$TMP/backups" \
    SSHPLUS_DB="$TMP/state/sshplus.db" \
    SSHPLUS_CONF="$TMP/etc/sshplus.conf" \
    SSHPLUS_OS_RELEASE="$TMP/os-release" \
    SSHPLUS_SYSTEMD_DIR="$TMP/systemd" \
    SSHPLUS_LOCAL_SBIN="$TMP/local-sbin" \
    SSHPLUS_LOCAL_BIN="$TMP/local-bin" \
    SSHPLUS_SSHD_DROPIN_DIR="$TMP/sshd" \
    SSHPLUS_TMPFILES_FILE="$TMP/tmpfiles/sshplus.conf" \
    SSHPLUS_LOGROTATE_FILE="$TMP/logrotate/sshplus" \
    SSHPLUS_API_GROUP=root \
    SSHPLUS_REPAIR_SKIP_PANEL=1 \
    SSHPLUS_REPAIR_SKIP_SYSTEMCTL=1 \
    SSHPLUS_REPAIR_SKIP_HEALTHCHECK=1 \
    SSHPLUS_REPAIR_SKIP_SSHD=1 \
        bash "$ROOT/bin/sshplus-repair"
}

run_repair
config_before="$(sha256sum "$TMP/etc/sshplus.conf" | awk '{print $1}')"
run_repair
config_after="$(sha256sum "$TMP/etc/sshplus.conf" | awk '{print $1}')"
[[ "$config_before" == "$config_after" ]]

[[ -s "$TMP/etc/sshplus.conf" ]]
grep -q '^SSHPLUS_PANEL_LISTEN="127.0.0.1:8088"$' "$TMP/etc/sshplus.conf"
[[ -L "$TMP/local-sbin/sshplus" && -e "$TMP/local-sbin/sshplus" ]]
[[ -L "$TMP/local-bin/menu" && -e "$TMP/local-bin/menu" ]]
[[ -L "$TMP/local-sbin/sshplus-agent" && -e "$TMP/local-sbin/sshplus-agent" ]]
[[ -L "$TMP/local-sbin/sshplus-healthcheck" && -e "$TMP/local-sbin/sshplus-healthcheck" ]]
[[ -L "$TMP/local-sbin/sshplus-panel-repair" && -e "$TMP/local-sbin/sshplus-panel-repair" ]]
[[ -L "$TMP/local-sbin/sshplus-repair" && -e "$TMP/local-sbin/sshplus-repair" ]]
[[ -f "$TMP/systemd/sshplus-expirer.timer" ]]
[[ -f "$TMP/systemd/sshplus-limiter.timer" ]]
[[ -f "$TMP/systemd/sshplus-metrics.timer" ]]
[[ -f "$TMP/state/sshplus.db" ]]
[[ "$(stat -c '%a' "$TMP/state/sshplus.db")" == 600 ]]
[[ "$(sqlite3 "$TMP/state/sshplus.db" 'PRAGMA quick_check;')" == ok ]]
[[ -f "$TMP/tmpfiles/sshplus.conf" ]]
[[ -f "$TMP/logrotate/sshplus" ]]

echo 'Teste integrado do reparador aprovado.'
