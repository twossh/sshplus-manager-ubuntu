#!/usr/bin/env bash
# Atualização segura do SSHPlus Manager por GitHub Releases.

SSHPLUS_REPOSITORY_FILE="${SSHPLUS_REPOSITORY_FILE:-${SSHPLUS_HOME}/REPOSITORY}"
SSHPLUS_GITHUB_API='https://api.github.com'

valid_github_repository() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

configured_repository() {
    local repo="${SSHPLUS_GITHUB_REPOSITORY:-}"
    if [[ -z "$repo" && -r "$SSHPLUS_REPOSITORY_FILE" ]]; then
        repo="$(tr -d '\r\n[:space:]' < "$SSHPLUS_REPOSITORY_FILE")"
    fi
    valid_github_repository "$repo" || return 1
    [[ "$repo" != SEU_USUARIO/* ]] || return 1
    printf '%s\n' "$repo"
}

configure_repository() {
    local current repo
    current="$(configured_repository 2>/dev/null || true)"
    header 'Configurar atualizações' 'Repositório GitHub no formato proprietário/repositório'
    repo="$(prompt_value 'Repositório GitHub' "$current")" || return 1
    valid_github_repository "$repo" || { error 'Formato inválido. Exemplo: usuario/sshplus-manager-ubuntu'; return 1; }
    [[ "$repo" != SEU_USUARIO/* ]] || { error 'Substitua SEU_USUARIO pelo usuário real do GitHub.'; return 1; }
    set_config_value "$SSHPLUS_CONF" SSHPLUS_GITHUB_REPOSITORY "$repo"
    SSHPLUS_GITHUB_REPOSITORY="$repo"
    ok "Repositório configurado: $repo"
}

github_latest_release_json() {
    local repo="$1"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 45 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "${SSHPLUS_GITHUB_API}/repos/${repo}/releases/latest"
}

release_info() {
    local repo="$1" json latest asset_name asset_url checksum_url
    json="$(github_latest_release_json "$repo")" || return 1
    latest="$(jq -r '.tag_name // empty' <<< "$json")"
    latest="${latest#v}"
    [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    asset_name="SSHPlus-Manager-ubuntu-26.04-v${latest}.tar.gz"
    asset_url="$(jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .browser_download_url' <<< "$json" | head -n1)"
    checksum_url="$(jq -r '.assets[]? | select(.name == "SHA256SUMS-release.txt") | .browser_download_url' <<< "$json" | head -n1)"
    [[ "$asset_url" == https://github.com/* && "$checksum_url" == https://github.com/* ]] || return 1
    printf '%s|%s|%s|%s\n' "$latest" "$asset_name" "$asset_url" "$checksum_url"
}

version_is_newer() {
    local current="$1" candidate="$2"
    [[ "$current" != "$candidate" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]]
}

check_for_updates() {
    local repo info_line latest current
    repo="$(configured_repository)" || {
        warn 'Repositório GitHub ainda não configurado.'
        printf 'Use: sudo sshplus --configure-repository\n'
        return 2
    }
    command -v curl >/dev/null 2>&1 || { error 'curl não está instalado.'; return 1; }
    command -v jq >/dev/null 2>&1 || { error 'jq não está instalado.'; return 1; }
    info_line="$(release_info "$repo")" || {
        error "Não foi possível consultar a última Release de $repo."
        return 1
    }
    IFS='|' read -r latest _ _ _ <<< "$info_line"
    current="$(sshplus_version)"
    printf 'Versão instalada: %s\n' "$current"
    printf 'Última versão:    %s\n' "$latest"
    printf 'Repositório:      %s\n' "$repo"
    if version_is_newer "$current" "$latest"; then
        warn "Atualização disponível: $current → $latest"
        return 10
    fi
    if [[ "$current" == "$latest" ]]; then
        ok 'O sistema já está atualizado.'
    else
        warn "A versão instalada ($current) é superior à Release estável ($latest)."
    fi
    return 0
}

verify_release_checksum() {
    local dir="$1" asset_name="$2" expected
    expected="$(awk -v file="$asset_name" '$2 == file || $2 == "*" file {print $1; exit}' "$dir/SHA256SUMS-release.txt")"
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || {
        error 'O arquivo de checksums não contém o artefato esperado.'
        return 1
    }
    printf '%s  %s\n' "$expected" "$asset_name" > "$dir/SHA256SUMS-selected.txt"
    (cd "$dir" && sha256sum -c --strict SHA256SUMS-selected.txt)
}

update_from_github() (
    local force="${1:-0}" repo info_line latest asset_name asset_url checksum_url current work source_dir
    require_root
    repo="$(configured_repository)" || {
        warn 'Configure primeiro o repositório GitHub.'
        configure_repository || return 1
        repo="$(configured_repository)" || return 1
    }
    apt_install curl jq ca-certificates tar gzip
    info_line="$(release_info "$repo")" || {
        error "Não foi possível localizar uma Release válida em $repo."
        return 1
    }
    IFS='|' read -r latest asset_name asset_url checksum_url <<< "$info_line"
    current="$(sshplus_version)"
    if [[ "$current" == "$latest" && "$force" != 1 ]]; then
        ok "A versão $current já está instalada."
        return 0
    fi
    if ! version_is_newer "$current" "$latest" && [[ "$force" != 1 ]]; then
        warn "A Release disponível ($latest) não é mais nova que a instalada ($current)."
        return 0
    fi
    printf 'Atualização: %s → %s\n' "$current" "$latest"
    printf 'Origem:     https://github.com/%s/releases/latest\n' "$repo"
    confirm 'Baixar, validar e instalar esta versão?' || return 0

    work="$(mktemp -d /tmp/sshplus-update.XXXXXX)"
    trap 'rm -rf "$work"' EXIT
    info "Baixando $asset_name..."
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300 \
        -o "$work/$asset_name" "$asset_url"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
        -o "$work/SHA256SUMS-release.txt" "$checksum_url"
    verify_release_checksum "$work" "$asset_name" || return 1
    tar -xzf "$work/$asset_name" -C "$work"
    source_dir="$work/SSHPlus-Manager-Ubuntu-26.04"
    [[ -x "$source_dir/install.sh" && -x "$source_dir/verify.sh" ]] || {
        error 'Estrutura inesperada no pacote da Release.'
        return 1
    }
    info 'Executando validação do pacote baixado...'
    NO_COLOR=1 bash "$source_dir/verify.sh" || {
        error 'A Release baixada falhou na validação; atualização cancelada.'
        return 1
    }
    info 'Instalando a atualização...'
    SSHPLUS_ASSUME_YES=1 bash "$source_dir/install.sh" --yes --skip-apt-update
    if [[ "$(sshplus_version)" == "$latest" ]]; then
        ok "SSHPlus Manager atualizado para $latest."
        log INFO "Atualização concluída: $current -> $latest ($repo)"
    else
        error 'A instalação terminou, mas a versão ativa não corresponde à Release.'
        return 1
    fi
)


rollback_snapshot_create() {
    local label="${1:-manual}" dir file version
    require_root
    [[ -d "$SSHPLUS_HOME" ]] || return 0
    dir="${SSHPLUS_BACKUP_DIR}/releases"; install -d -m 0700 "$dir"
    version="$(sshplus_version)"
    file="${dir}/sshplus-release-$(date +%Y%m%d-%H%M%S)-v${version}-${label}.tar.gz"
    tar --numeric-owner -C / -czf "$file" "${SSHPLUS_HOME#/}" || return 1
    tar -tzf "$file" >/dev/null || { rm -f "$file"; return 1; }
    chmod 0600 "$file"
    printf '%s\n' "$file"
}

rollback_list_json() {
    local dir="${SSHPLUS_BACKUP_DIR}/releases" first=1 file size created
    printf '{"ok":true,"data":['
    shopt -s nullglob
    for file in "$dir"/sshplus-release-*.tar.gz; do
        size="$(stat -c %s "$file")"; created="$(stat -c %Y "$file")"
        (( first == 1 )) || printf ','; first=0
        jq -cn --arg file "$file" --argjson size "$size" --argjson created_at "$created" '{file:$file,size_bytes:$size,created_at:$created_at}'
    done
    shopt -u nullglob
    printf ']}\n'
}

rollback_apply() (
    local file="$1" actor="${2:-root}" source="${3:-cli}" dir temp extracted snapshot
    require_root
    dir="${SSHPLUS_BACKUP_DIR}/releases"
    [[ -f "$file" && "$file" == "$dir"/sshplus-release-*.tar.gz ]] || return 2
    tar -tzf "$file" >/dev/null 2>&1 || return 2
    tar -tzf "$file" | grep -Eq '(^/|(^|/)\.\.(/|$))' && return 2
    tar -tzf "$file" | grep -q '^opt/sshplus/' || return 2
    snapshot="$(rollback_snapshot_create before-rollback)" || return 1
    temp="$(mktemp -d /tmp/sshplus-rollback.XXXXXX)"; trap 'rm -rf "$temp"' EXIT
    tar -xzf "$file" -C "$temp"
    extracted="$temp/opt/sshplus"
    [[ -x "$extracted/bin/sshplus" && -r "$extracted/VERSION" ]] || return 2
    rm -rf "${SSHPLUS_HOME}.rollback-new"; mv "$extracted" "${SSHPLUS_HOME}.rollback-new"
    rm -rf "${SSHPLUS_HOME}.rollback-old"; mv "$SSHPLUS_HOME" "${SSHPLUS_HOME}.rollback-old"
    if mv "${SSHPLUS_HOME}.rollback-new" "$SSHPLUS_HOME"; then
        rm -rf "${SSHPLUS_HOME}.rollback-old"
        systemctl daemon-reload
        systemctl restart sshplus-expirer.timer sshplus-limiter.timer sshplus-metrics.timer nginx.service php8.5-fpm.service 2>/dev/null || true
        audit_log "$actor" "$source" update.rollback "$file" 1 "snapshot=$snapshot"
        return 0
    fi
    rm -rf "$SSHPLUS_HOME"; mv "${SSHPLUS_HOME}.rollback-old" "$SSHPLUS_HOME" 2>/dev/null || true
    audit_log "$actor" "$source" update.rollback "$file" 0
    return 1
)

rollback_cli() {
    local file
    ls -lh "${SSHPLUS_BACKUP_DIR}/releases"/sshplus-release-*.tar.gz 2>/dev/null || { warn 'Nenhum rollback disponível.'; return; }
    read -r -e -p 'Arquivo para restaurar: ' file
    confirm "Aplicar rollback usando $file?" || return
    rollback_apply "$file" root cli && ok "Rollback concluído. Versão ativa: $(sshplus_version)" || error 'Falha no rollback.'
}

update_menu() {
    local option rc
    while true; do
        header 'Atualização do SSHPlus' 'GitHub Releases com validação SHA-256'
        printf '  Repositório: %s\n' "$(configured_repository 2>/dev/null || printf 'não configurado')"
        printf '  Versão:      %s\n\n' "$(sshplus_version)"
        printf '  1) Verificar atualização\n'
        printf '  2) Atualizar agora\n'
        printf '  3) Reinstalar última Release\n'
        printf '  4) Configurar repositório\n'
        printf '  5) Listar pontos de rollback\n'
        printf '  6) Aplicar rollback\n'
        printf '  0) Voltar\n\n'
        read -r -p 'Opção: ' option || return 0
        case "$option" in
            1)
                rc=0; check_for_updates || rc=$?
                [[ $rc -eq 10 ]] || true
                pause
                ;;
            2) update_from_github 0; pause ;;
            3) update_from_github 1; pause ;;
            4) configure_repository; pause ;;
            5) rollback_list_json | jq .; pause ;;
            6) rollback_cli; pause ;;
            0) return 0 ;;
            *) warn 'Opção inválida.'; sleep 1 ;;
        esac
    done
}
