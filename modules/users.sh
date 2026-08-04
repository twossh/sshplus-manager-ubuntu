#!/usr/bin/env bash

# Compatibilidade interna com nomes usados nas versões 4.x.
db_find() { db_user_find "$1"; }
db_upsert() { db_user_upsert "$@"; }
db_remove() { db_user_remove "$1"; }

create_ssh_user() {
    require_root
    local user password limit expiry_input expiry_epoch=0
    header 'Criar usuário SSH' 'Conta local com limite de sessões e expiração opcional'
    user="$(prompt_value 'Usuário')" || return
    password="$(prompt_secret_confirmed 'Senha')" || return
    limit="$(prompt_value 'Limite de conexões' '1')" || return
    expiry_input="$(prompt_value 'Expiração AAAA-MM-DD (vazio = sem expiração)')" || return
    if [[ -n "$expiry_input" ]]; then
        valid_date "$expiry_input" || { error 'Data inválida.'; return; }
        expiry_epoch="$(date -d "$expiry_input 23:59:59" +%s)"
    fi
    managed_user_create "$user" "$password" "$limit" "$expiry_epoch" normal root cli && ok "Usuário $user criado."
}

create_test_user() {
    require_root
    local user password hours limit expiry_epoch
    header 'Criar usuário de teste' 'Conta temporária com expiração em horas'
    user="$(prompt_value 'Usuário')" || return
    password="$(prompt_secret_confirmed 'Senha')" || return
    hours="$(prompt_value 'Validade em horas' '2')" || return
    limit="$(prompt_value 'Limite de conexões' '1')" || return
    valid_positive_int "$hours" || { error 'Prazo inválido.'; return; }
    expiry_epoch="$(( $(date +%s) + hours * 3600 ))"
    managed_user_create "$user" "$password" "$limit" "$expiry_epoch" test root cli && ok "Usuário de teste $user criado até $(format_epoch "$expiry_epoch")."
}

list_ssh_users() {
    header 'Usuários gerenciados' 'Banco SQLite'
    printf '%-18s %-8s %-20s %-10s %-10s\n' 'USUÁRIO' 'LIMITE' 'EXPIRAÇÃO' 'SESSÕES' 'STATUS'
    separator 72
    while IFS='|' read -r user limit expiry _created _type status; do
        [[ -n "$user" ]] || continue
        if id "$user" >/dev/null 2>&1; then
            [[ "$(passwd -S "$user" 2>/dev/null | awk '{print $2}')" == L ]] && status='bloqueado'
            printf '%-18s %-8s %-20s %-10s %-10s\n' "$user" "$limit" "$(format_epoch "$expiry")" "$(count_user_sessions "$user")" "$status"
        else
            printf '%-18s %-8s %-20s %-10s %-10s\n' "$user" "$limit" "$(format_epoch "$expiry")" '-' 'ausente'
        fi
    done < <(db_users_all)
}

change_user_password() {
    local user password
    user="$(prompt_managed_user 'Usuário')" || return
    password="$(prompt_secret_confirmed 'Nova senha')" || return
    managed_user_set_password "$user" "$password" root cli && ok 'Senha alterada.' || error 'Não foi possível alterar a senha.'
}

change_user_limit() {
    local user limit
    user="$(prompt_managed_user 'Usuário')" || return
    limit="$(prompt_value 'Novo limite')" || return
    managed_user_set_limit "$user" "$limit" root cli && ok 'Limite atualizado.' || error 'Limite inválido.'
}

change_user_expiry() {
    local user value expiry=0 unlock=0
    user="$(prompt_managed_user 'Usuário')" || return
    value="$(prompt_value 'Nova data AAAA-MM-DD (vazio = remover expiração)')" || return
    if [[ -n "$value" ]]; then valid_date "$value" || { error 'Data inválida.'; return; }; expiry="$(date -d "$value 23:59:59" +%s)"; fi
    confirm 'Desbloquear a conta caso estivesse expirada?' && unlock=1
    managed_user_set_expiry "$user" "$expiry" "$unlock" root cli && ok 'Expiração atualizada.' || error 'Não foi possível atualizar a expiração.'
}

lock_unlock_user() {
    local user desired
    user="$(prompt_managed_user 'Usuário')" || return
    if [[ "$(passwd -S "$user" 2>/dev/null | awk '{print $2}')" == L ]]; then desired=active; else desired=blocked; fi
    managed_user_set_status "$user" "$desired" root cli && ok "Status atualizado: $desired." || error 'Não foi possível atualizar o status; verifique a expiração.'
}

delete_ssh_user() {
    local user
    user="$(prompt_managed_user 'Usuário')" || return
    confirm "Excluir $user e seu diretório pessoal?" || return
    managed_user_delete "$user" 1 root cli && ok 'Usuário removido.'
}

users_menu() {
    local option
    while true; do
        header 'Gerenciamento de usuários SSH' 'SQLite, auditoria e limites de sessão'
        printf '  1) Criar usuário\n  2) Criar usuário de teste\n  3) Listar usuários\n'
        printf '  4) Alterar senha\n  5) Alterar limite\n  6) Alterar expiração\n'
        printf '  7) Bloquear/desbloquear\n  8) Remover usuário\n  0) Voltar\n\n'
        read -r -p 'Opção: ' option || return
        case "$option" in
            1) create_ssh_user; pause ;; 2) create_test_user; pause ;; 3) list_ssh_users; pause ;;
            4) change_user_password; pause ;; 5) change_user_limit; pause ;; 6) change_user_expiry; pause ;;
            7) lock_unlock_user; pause ;; 8) delete_ssh_user; pause ;; 0) return ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
