#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mapfile -t scripts < <(find . -type f \( -name '*.sh' -o -path './bin/*' \) \
    -not -path './dist/*' -print | LC_ALL=C sort)

for file in "${scripts[@]}"; do
    bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=error -x -e SC1090,SC1091 "${scripts[@]}"
else
    printf 'Aviso: ShellCheck não instalado; lint avançado ignorado.\n' >&2
fi

bash ./scripts/checksums.sh check
bash ./verify.sh
bash ./scripts/build-release.sh

# Valida os checksums da Release e o nome usado pelo instalador online.
(
    cd "$ROOT/dist"
    sha256sum -c --strict SHA256SUMS-release.txt >/dev/null
)
release_asset='SSHPlus-Manager-ubuntu-lts-latest.tar.gz'
release_checksum="$(awk -v file="$release_asset" '
    NF >= 2 {
        checksum=$1
        name=$2
        sub(/^\*/, "", name)
        sub(/^\.\//, "", name)
        if (name == file) { print checksum; exit }
    }
' "$ROOT/dist/SHA256SUMS-release.txt")"
[[ "$release_checksum" =~ ^[a-fA-F0-9]{64}$ ]] || {
    printf 'Checksum do instalador online não encontrado para %s.\n' "$release_asset" >&2
    exit 1
}

if [[ "${SSHPLUS_RUN_PANEL_INTEGRATION:-0}" == 1 ]]; then
    bash ./scripts/test-panel-integration.sh
fi
