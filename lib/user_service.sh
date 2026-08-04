#!/usr/bin/env bash
# Operações não interativas para contas gerenciadas.

managed_user_create() {
    local user="$1" password="$2" limit="$3" expiry_epoch="$4" type="${5:-normal}" actor="${6:-root}" source="${7:-cli}"
    valid_username "$user" || { error 'Nome de usuário inválido.'; return 2; }
    valid_password "$password" || { error 'Senha inválida: use no mínimo 8 caracteres.'; return 2; }
    valid_positive_int "$limit" || { error 'Limite inválido.'; return 2; }
    [[ "$expiry_epoch" =~ ^[0-9]+$ ]] || { error 'Expiração inválida.'; return 2; }
    [[ "$type" =~ ^(normal|test|migrated)$ ]] || return 2
    id "$user" >/dev/null 2>&1 && { error 'O usuário Linux já existe.'; return 3; }
    db_user_exists "$user" && { error 'O usuário já está no banco.'; return 3; }
    if ! useradd --create-home --user-group --shell /bin/bash "$user"; then
        audit_log "$actor" "$source" user.create "$user" 0 'useradd falhou'
        return 1
    fi
    if ! printf '%s:%s\n' "$user" "$password" | chpasswd; then
        userdel --remove "$user" 2>/dev/null || true
        audit_log "$actor" "$source" user.create "$user" 0 'chpasswd falhou'
        return 1
    fi
    if (( expiry_epoch > 0 )); then
        chage -E "$(date -d "@${expiry_epoch} +1 day" +%F)" "$user"
    fi
    db_user_upsert "$user" "$limit" "$expiry_epoch" "$(date +%s)" "$type" active
    audit_log "$actor" "$source" user.create "$user" 1 "limite=$limit tipo=$type expira=$expiry_epoch"
}

managed_user_set_password() {
    local user="$1" password="$2" actor="${3:-root}" source="${4:-cli}" row limit expiry created type status
    db_user_exists "$user" || return 3
    valid_password "$password" || return 2
    printf '%s:%s\n' "$user" "$password" | chpasswd || { audit_log "$actor" "$source" user.password "$user" 0; return 1; }
    row="$(db_user_find "$user")"; IFS='|' read -r _ limit expiry created type status <<< "$row"
    if (( expiry > 0 && expiry <= $(date +%s) )); then
        passwd -l "$user" >/dev/null 2>&1 || true; status=expired
    else
        passwd -u "$user" >/dev/null 2>&1 || true; status=active
    fi
    db_user_upsert "$user" "$limit" "$expiry" "$created" "$type" "$status"
    audit_log "$actor" "$source" user.password "$user" 1
}

managed_user_set_limit() {
    local user="$1" limit="$2" actor="${3:-root}" source="${4:-cli}" row expiry created type status
    db_user_exists "$user" || return 3
    valid_positive_int "$limit" || return 2
    row="$(db_user_find "$user")"; IFS='|' read -r _ _ expiry created type status <<< "$row"
    db_user_upsert "$user" "$limit" "$expiry" "$created" "$type" "$status"
    audit_log "$actor" "$source" user.limit "$user" 1 "limite=$limit"
}

managed_user_set_expiry() {
    local user="$1" expiry="$2" unlock="${3:-0}" actor="${4:-root}" source="${5:-cli}" row limit created type status
    db_user_exists "$user" || return 3
    [[ "$expiry" =~ ^[0-9]+$ ]] || return 2
    (( expiry == 0 || expiry > $(date +%s) )) || return 2
    row="$(db_user_find "$user")"; IFS='|' read -r _ limit _ created type status <<< "$row"
    if (( expiry > 0 )); then
        chage -E "$(date -d "@${expiry} +1 day" +%F)" "$user"
    else
        chage -E -1 "$user"
    fi
    if [[ "$unlock" == 1 && "$status" == expired ]]; then
        passwd -u "$user" >/dev/null 2>&1 || true; status=active
    fi
    db_user_upsert "$user" "$limit" "$expiry" "$created" "$type" "$status"
    audit_log "$actor" "$source" user.expiry "$user" 1 "expira=$expiry"
}

managed_user_set_status() {
    local user="$1" desired="$2" actor="${3:-root}" source="${4:-cli}" row limit expiry created type status
    db_user_exists "$user" || return 3
    row="$(db_user_find "$user")"; IFS='|' read -r _ limit expiry created type status <<< "$row"
    case "$desired" in
        active)
            (( expiry == 0 || expiry > $(date +%s) )) || return 4
            passwd -u "$user" >/dev/null 2>&1 || true; status=active ;;
        blocked)
            passwd -l "$user" >/dev/null; pkill -KILL -u "$user" 2>/dev/null || true; status=blocked ;;
        *) return 2 ;;
    esac
    db_user_upsert "$user" "$limit" "$expiry" "$created" "$type" "$status"
    audit_log "$actor" "$source" user.status "$user" 1 "status=$status"
}

managed_user_delete() {
    local user="$1" remove_home="${2:-1}" actor="${3:-root}" source="${4:-cli}"
    db_user_exists "$user" || return 3
    pkill -KILL -u "$user" 2>/dev/null || true
    if [[ "$remove_home" == 1 ]]; then userdel --remove "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
    else userdel "$user" 2>/dev/null || true; fi
    db_user_remove "$user"
    audit_log "$actor" "$source" user.delete "$user" 1 "remove_home=$remove_home"
}
