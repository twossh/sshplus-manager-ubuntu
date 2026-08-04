#!/usr/bin/env bash
set -uo pipefail
umask 027
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
failed=0; warnings=0
pass(){ printf '[OK] %s\n' "$*"; }
fail(){ printf '[ERRO] %s\n' "$*" >&2; ((failed++)); }
notice(){ printf '[AVISO] %s\n' "$*"; ((warnings++)); }

printf 'SSHPlus Manager %s — verificação\n\n' "$(tr -d '\r\n' < "$BASE_DIR/VERSION")"
required=(VERSION TARGET REPOSITORY README.md CHANGELOG.md install.sh uninstall.sh install-online.sh
  bin/sshplus bin/sshplus-agent bin/sshplus-expirer bin/sshplus-limiter bin/sshplus-metrics bin/sshplus-healthcheck
  lib/common.sh lib/database.sh lib/user_service.sh modules/users.sh modules/panel.sh modules/update.sh modules/backup.sh
  database/schema.sql api/bootstrap.php api/AgentClient.php api/router.php web/public/index.php web/public/assets/app.css web/public/assets/app.js
  nginx/sshplus-panel.conf.template sudoers/sshplus-api systemd/sshplus-metrics.service systemd/sshplus-metrics.timer)
for item in "${required[@]}"; do [[ -f "$BASE_DIR/$item" ]] && pass "Arquivo presente: $item" || fail "Arquivo ausente: $item"; done

version="$(tr -d '\r\n' < "$BASE_DIR/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && pass "Versão semântica: $version" || fail 'VERSION inválido.'
[[ "$(tr -d '\r\n' < "$BASE_DIR/TARGET")" == ubuntu-26.04 ]] && pass 'Alvo Ubuntu 26.04.' || fail 'TARGET inválido.'

mapfile -t scripts < <(find "$BASE_DIR" -type f \( -name '*.sh' -o -path "$BASE_DIR/bin/*" \) -not -path '*/dist/*' -print | sort)
for file in "${scripts[@]}"; do bash -n "$file" || fail "Sintaxe Bash: ${file#$BASE_DIR/}"; done
(( failed == 0 )) && pass 'Sintaxe Bash validada.'

if command -v php >/dev/null 2>&1; then
  while IFS= read -r file; do php -l "$file" >/dev/null || fail "Sintaxe PHP: ${file#$BASE_DIR/}"; done < <(find "$BASE_DIR/api" "$BASE_DIR/web" -type f -name '*.php' -print)
  pass "Sintaxe PHP validada com $(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')."
else notice 'PHP CLI indisponível; lint PHP ignorado.'; fi
if command -v node >/dev/null 2>&1; then node --check "$BASE_DIR/web/public/assets/app.js" >/dev/null && pass 'JavaScript validado.' || fail 'JavaScript inválido.'; else notice 'Node.js indisponível; lint JavaScript ignorado.'; fi

if [[ -f "$BASE_DIR/SHA256SUMS" ]]; then (cd "$BASE_DIR" && sha256sum -c --quiet SHA256SUMS) && pass 'Checksums internos válidos.' || fail 'Checksums internos inválidos.'; else notice 'SHA256SUMS ainda não gerado.'; fi

if grep -RIEq '\bdialog\b|programbox|msgbox|passwordbox|inputbox' "$BASE_DIR/bin" "$BASE_DIR/lib" "$BASE_DIR/modules" "$BASE_DIR/install.sh" 2>/dev/null; then fail 'Referência à interface dialog encontrada.'; else pass 'Interface sem dependência dialog.'; fi
if grep -RIEq 'apt-key|/etc/rc\.local|\bscreen\b|python2|python-pip|squid3' "$BASE_DIR/bin" "$BASE_DIR/lib" "$BASE_DIR/modules" "$BASE_DIR/install.sh" "$BASE_DIR/systemd" 2>/dev/null; then fail 'Técnica legada proibida encontrada.'; else pass 'Nenhuma técnica legada proibida.'; fi
if grep -RIEq 'BEGIN (RSA |OPENSSH )?PRIVATE KEY' "$BASE_DIR" --exclude-dir=.git --exclude=verify.sh 2>/dev/null; then fail 'Possível chave privada incluída.'; else pass 'Nenhuma chave privada incluída.'; fi
if grep -RIEq 'new[[:space:]]+(PDO|SQLite3)|sqlite:file:' "$BASE_DIR/api" 2>/dev/null; then fail 'A API PHP não deve abrir o banco administrativo diretamente.'; else pass 'Banco administrativo isolado da API PHP.'; fi
if find "$BASE_DIR" -type f -perm -0002 -print -quit | grep -q .; then fail 'Arquivo world-writable encontrado.'; else pass 'Permissões do pacote sem world-writable.'; fi

if command -v sqlite3 >/dev/null 2>&1; then
  temp="$(mktemp -d /tmp/sshplus-verify.XXXXXX)"; trap 'rm -rf "$temp"' EXIT
  sqlite3 "$temp/test.db" < "$BASE_DIR/database/schema.sql" || fail 'Falha ao criar banco SQLite.'
  tables="$(sqlite3 "$temp/test.db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('users','audit_logs','api_users','servers','metrics','backups');")"
  [[ "$tables" == 6 ]] && pass 'Esquema SQLite completo.' || fail 'Esquema SQLite incompleto.'
  export SSHPLUS_HOME="$BASE_DIR" SSHPLUS_CONFIG_DIR="$temp/etc" SSHPLUS_STATE_DIR="$temp/state" SSHPLUS_LOG_DIR="$temp/log" SSHPLUS_DB="$temp/state/sshplus.db" SSHPLUS_BACKUP_DIR="$temp/backups"
  source "$BASE_DIR/lib/common.sh"; source "$BASE_DIR/lib/database.sh"
  ensure_runtime_dirs
  db_user_upsert testuser 2 0 100 normal active
  [[ "$(db_user_find testuser)" == 'testuser|2|0|100|normal|active' ]] && pass 'SQLite: inclusão e leitura.' || fail 'SQLite: falha de leitura.'
  audit_log verifier test test.event target 1 details
  [[ "$(db_query "SELECT count(*) FROM audit_logs;")" == 1 ]] && pass 'SQLite: auditoria.' || fail 'SQLite: auditoria falhou.'
  db_user_remove testuser
  if db_user_exists testuser; then fail 'SQLite: remoção falhou.'; else pass 'SQLite: remoção.'; fi
else notice 'sqlite3 indisponível; testes funcionais do banco ignorados.'; fi

if command -v visudo >/dev/null 2>&1; then visudo -cf "$BASE_DIR/sudoers/sshplus-api" >/dev/null && pass 'Política sudoers válida.' || fail 'Política sudoers inválida.'; else notice 'visudo indisponível.'; fi
if command -v systemd-analyze >/dev/null 2>&1; then
  output="$(systemd-analyze verify "$BASE_DIR"/systemd/*.service "$BASE_DIR"/systemd/*.timer 2>&1)"; rc=$?
  (( rc == 0 )) && pass 'Unidades systemd validadas.' || { notice 'systemd-analyze retornou avisos dependentes do ambiente.'; [[ -n "$output" ]] && printf '%s\n' "$output" | sed 's/^/    /'; }
else notice 'systemd-analyze indisponível.'; fi

if [[ -r /etc/os-release ]]; then source /etc/os-release; [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 26.04 ]] && pass 'Ubuntu 26.04 detectado.' || notice "Ambiente atual: ${PRETTY_NAME:-desconhecido}; alvo oficial Ubuntu 26.04."; fi
printf '\nResultado: %s aviso(s), %s erro(s).\n' "$warnings" "$failed"
(( failed == 0 ))
