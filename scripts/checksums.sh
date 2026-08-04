#!/usr/bin/env bash
set -euo pipefail
umask 027

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-check}"
CHECKSUM_FILE="$ROOT/SHA256SUMS"

collect_files() {
    cd "$ROOT"
    {
        printf '%s\n' \
            CHANGELOG.md CONTRIBUTING.md LICENSE NOTICE README.md SECURITY.md SUPPORT.md \
            REPOSITORY TARGET VERSION install-online.sh install.sh uninstall.sh verify.sh
        find api bin config database docs lib modules nginx site sudoers systemd web -type f -print
    } | LC_ALL=C sort -u
}

generate() {
    local tmp
    tmp="$(mktemp "$ROOT/.SHA256SUMS.XXXXXX")"
    trap 'rm -f "$tmp"' RETURN
    (
        cd "$ROOT"
        while IFS= read -r file; do
            [[ -f "$file" ]] || { printf 'Arquivo ausente: %s\n' "$file" >&2; exit 1; }
            sha256sum -- "$file"
        done < <(collect_files)
    ) > "$tmp"
    mv -f "$tmp" "$CHECKSUM_FILE"
    chmod 0644 "$CHECKSUM_FILE"
    printf 'Checksums atualizados: %s\n' "$CHECKSUM_FILE"
}

check() {
    [[ -f "$CHECKSUM_FILE" ]] || { printf 'SHA256SUMS não encontrado.\n' >&2; exit 1; }
    (cd "$ROOT" && sha256sum -c --strict SHA256SUMS)
}

case "$MODE" in
    generate|update) generate ;;
    check|verify) check ;;
    *) printf 'Uso: %s [check|generate]\n' "$0" >&2; exit 2 ;;
esac
