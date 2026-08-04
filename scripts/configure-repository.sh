#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${1:-}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    printf 'Uso: %s PROPRIETARIO/REPOSITORIO\n' "$0" >&2
    exit 2
}
old_repo="$(tr -d '\r\n[:space:]' < "$ROOT/REPOSITORY" 2>/dev/null || printf 'SEU_USUARIO/sshplus-manager-ubuntu')"
printf '%s\n' "$repo" > "$ROOT/REPOSITORY"

replace_in_file() {
    local file="$1" content
    [[ -f "$file" ]] || return 0
    content="$(cat "$file")"
    content="${content//SEU_USUARIO\/sshplus-manager-ubuntu/$repo}"
    if [[ -n "$old_repo" && "$old_repo" != "$repo" ]]; then
        content="${content//$old_repo/$repo}"
    fi
    printf '%s\n' "$content" > "$file"
}

replace_in_file "$ROOT/install-online.sh"
replace_in_file "$ROOT/README.md"
replace_in_file "$ROOT/docs/GITHUB.md"
replace_in_file "$ROOT/docs/ATUALIZACAO.md"
chmod 0644 "$ROOT/REPOSITORY"
chmod 0755 "$ROOT/install-online.sh"
printf 'Repositório configurado: %s\n' "$repo"
printf 'Agora execute: make checksums && make verify\n'
