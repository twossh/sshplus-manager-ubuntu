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
