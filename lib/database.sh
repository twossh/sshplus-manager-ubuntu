#!/usr/bin/env bash
# Camada SQLite central do SSHPlus Manager 5.

sqlite_escape() {
    printf '%s' "${1//\'/\'\'}"
}

db_exec() {
    local sql="$1"
    sqlite3 -batch -cmd '.timeout 5000' "$SSHPLUS_DB" "$sql"
}

db_query() {
    local sql="$1"
    sqlite3 -batch -noheader -cmd '.timeout 5000' -separator '|' "$SSHPLUS_DB" "$sql"
}

db_query_json() {
    local sql="$1"
    sqlite3 -batch -json -cmd '.timeout 5000' "$SSHPLUS_DB" "$sql"
}

db_is_sqlite() {
    [[ -f "$1" ]] || return 1
    [[ "$(head -c 15 "$1" 2>/dev/null || true)" == 'SQLite format 3' ]]
}

db_init() {
    command -v sqlite3 >/dev/null 2>&1 || { error 'sqlite3 não está instalado.'; return 1; }
    install -d -m 0750 "$SSHPLUS_STATE_DIR"
    if [[ -e "$SSHPLUS_DB" && -s "$SSHPLUS_DB" ]] && ! db_is_sqlite "$SSHPLUS_DB"; then
        error "O banco $SSHPLUS_DB não é um arquivo SQLite válido."
        return 1
    fi
    if [[ ! -s "$SSHPLUS_DB" ]]; then
        sqlite3 "$SSHPLUS_DB" < "$SSHPLUS_HOME/database/schema.sql"
    else
        sqlite3 "$SSHPLUS_DB" < "$SSHPLUS_HOME/database/schema.sql" >/dev/null
    fi
    if (( EUID == 0 )); then
        chown root:root "$SSHPLUS_DB" "$SSHPLUS_STATE_DIR"
        chmod 0750 "$SSHPLUS_STATE_DIR"
        chmod 0600 "$SSHPLUS_DB"
    else
        chmod 0700 "$SSHPLUS_STATE_DIR"
        chmod 0600 "$SSHPLUS_DB"
    fi
}

db_migrate_legacy() {
    local source="$1" backup row user limit expiry created type status
    [[ -f "$source" && -s "$source" ]] || return 0
    db_is_sqlite "$source" && return 0
    backup="${source}.legacy-$(date +%Y%m%d-%H%M%S)"
    cp -a "$source" "$backup"
    info "Migrando banco legado: $source"
    while IFS= read -r row || [[ -n "$row" ]]; do
        [[ -n "$row" ]] || continue
        if [[ "$row" == *'|'* ]]; then
            IFS='|' read -r user limit expiry created type status <<< "$row"
        else
            read -r user limit _ <<< "$row"
            expiry=0; created="$(date +%s)"; type='migrated'; status='active'
        fi
        valid_username "${user:-}" || continue
        valid_positive_int "${limit:-}" || limit=1
        [[ "${expiry:-}" =~ ^[0-9]+$ ]] || expiry=0
        [[ "${created:-}" =~ ^[0-9]+$ ]] || created="$(date +%s)"
        [[ "${type:-}" =~ ^(normal|test|migrated)$ ]] || type='migrated'
        [[ "${status:-}" =~ ^(active|blocked|expired|missing)$ ]] || status='active'
        id "$user" >/dev/null 2>&1 || continue
        db_user_upsert "$user" "$limit" "$expiry" "$created" "$type" "$status"
    done < "$source"
    ok "Migração concluída. Cópia preservada em $backup"
}

db_user_exists() {
    local user; user="$(sqlite_escape "$1")"
    [[ "$(db_query "SELECT count(*) FROM users WHERE username='$user';")" == 1 ]]
}

db_user_find() {
    local user; user="$(sqlite_escape "$1")"
    db_query "SELECT username,max_sessions,expires_at,created_at,user_type,status FROM users WHERE username='$user' LIMIT 1;"
}

db_users_all() {
    db_query 'SELECT username,max_sessions,expires_at,created_at,user_type,status FROM users ORDER BY username COLLATE NOCASE;'
}

db_users_json() {
    db_query_json 'SELECT username,max_sessions,expires_at,created_at,updated_at,user_type,status FROM users ORDER BY username COLLATE NOCASE;'
}

db_user_upsert() {
    local user limit expiry created type status now
    user="$(sqlite_escape "$1")"; limit="$2"; expiry="$3"; created="$4"
    type="$(sqlite_escape "$5")"; status="$(sqlite_escape "$6")"; now="$(date +%s)"
    db_exec "BEGIN IMMEDIATE;
      INSERT INTO users(username,max_sessions,expires_at,created_at,updated_at,user_type,status)
      VALUES('$user',$limit,$expiry,$created,$now,'$type','$status')
      ON CONFLICT(username) DO UPDATE SET
        max_sessions=excluded.max_sessions,
        expires_at=excluded.expires_at,
        updated_at=excluded.updated_at,
        user_type=excluded.user_type,
        status=excluded.status;
      COMMIT;"
}

db_user_remove() {
    local user; user="$(sqlite_escape "$1")"
    db_exec "DELETE FROM users WHERE username='$user';"
}

audit_log() {
    local actor="${1:-system}" source="${2:-cli}" action="${3:-unknown}" target="${4:-}" success="${5:-1}" details="${6:-}" remote="${7:-}"
    actor="$(sqlite_escape "$actor")"; source="$(sqlite_escape "$source")"; action="$(sqlite_escape "$action")"
    target="$(sqlite_escape "$target")"; details="$(sqlite_escape "$details")"; remote="$(sqlite_escape "$remote")"
    [[ "$success" == 0 || "$success" == 1 ]] || success=0
    db_exec "INSERT INTO audit_logs(created_at,actor,source,action,target,success,details,remote_addr)
             VALUES($(date +%s),'$actor','$source','$action','$target',$success,'$details','$remote');" >/dev/null 2>&1 || true
}

db_audit_json() {
    local limit="${1:-100}"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=100
    (( limit > 500 )) && limit=500
    db_query_json "SELECT id,created_at,actor,source,action,target,success,details,remote_addr FROM audit_logs ORDER BY id DESC LIMIT $limit;"
}

db_api_user_upsert() {
    local username hash role now
    username="$(sqlite_escape "$1")"; hash="$(sqlite_escape "$2")"; role="$(sqlite_escape "${3:-admin}")"; now="$(date +%s)"
    db_exec "INSERT INTO api_users(username,password_hash,role,active,created_at,updated_at)
      VALUES('$username','$hash','$role',1,$now,$now)
      ON CONFLICT(username) DO UPDATE SET password_hash=excluded.password_hash,role=excluded.role,active=1,updated_at=excluded.updated_at;"
}

db_metrics_json() {
    local limit="${1:-72}"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=72
    (( limit < 1 )) && limit=1
    (( limit > 288 )) && limit=288
    db_query_json "SELECT recorded_at,cpu_load,memory_used_bytes,memory_total_bytes,disk_used_bytes,disk_total_bytes,rx_bytes,tx_bytes FROM metrics ORDER BY id DESC LIMIT $limit;"
}

db_server_list_json() {
    db_query_json 'SELECT id,name,endpoint,status,is_local,created_at,updated_at FROM servers ORDER BY is_local DESC,name;'
}

db_server_add() {
    local name endpoint now
    name="$(sqlite_escape "$1")"; endpoint="$(sqlite_escape "$2")"; now="$(date +%s)"
    db_exec "INSERT INTO servers(name,endpoint,status,is_local,created_at,updated_at) VALUES('$name','$endpoint','unknown',0,$now,$now);"
}

db_server_remove() {
    local id="$1"
    [[ "$id" =~ ^[0-9]+$ ]] || return 1
    db_exec "DELETE FROM servers WHERE id=$id AND is_local=0;"
}
