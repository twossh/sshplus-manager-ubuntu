#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
    cat <<'USAGE'
Uso:
  ./scripts/prepare-release.sh patch "Resumo da versão"
  ./scripts/prepare-release.sh minor "Resumo da versão"
  ./scripts/prepare-release.sh major "Resumo da versão"
  ./scripts/prepare-release.sh set X.Y.Z "Resumo da versão"

Opção final:
  --commit   cria o commit e a tag local, mas não envia ao GitHub
USAGE
}

mode="${1:-}"
[[ -n "$mode" ]] || { usage >&2; exit 2; }
shift

if [[ "$mode" == set ]]; then
    explicit="${1:-}"
    [[ -n "$explicit" ]] || { usage >&2; exit 2; }
    shift
fi

notes="${1:-}"
[[ -n "$notes" ]] || { printf 'Informe um resumo da versão.\n' >&2; usage >&2; exit 2; }
shift

commit_release=0
if [[ "${1:-}" == '--commit' ]]; then
    commit_release=1
    shift
fi
(( $# == 0 )) || { usage >&2; exit 2; }

backup_dir="$(mktemp -d /tmp/sshplus-prepare-release.XXXXXX)"
cp VERSION CHANGELOG.md SHA256SUMS "$backup_dir/"
completed=0
cleanup() {
    if (( completed == 0 )); then
        cp "$backup_dir/VERSION" VERSION
        cp "$backup_dir/CHANGELOG.md" CHANGELOG.md
        cp "$backup_dir/SHA256SUMS" SHA256SUMS
        printf 'Preparação interrompida; VERSION, CHANGELOG.md e SHA256SUMS foram restaurados.\n' >&2
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

old_version="$(cat VERSION)"
if [[ "$mode" == set ]]; then
    bash ./scripts/version.sh set "$explicit"
else
    bash ./scripts/version.sh bump "$mode"
fi
new_version="$(cat VERSION)"
release_date="$(date +%F)"

python3 - "$new_version" "$release_date" "$notes" <<'PY'
from pathlib import Path
import sys
version, date, notes = sys.argv[1:]
p = Path('CHANGELOG.md')
s = p.read_text()
marker = '## [Unreleased]'
if marker not in s:
    raise SystemExit('CHANGELOG.md não contém a seção [Unreleased].')
entry = f"{marker}\n\n## [{version}] - {date}\n\n### Alterado\n\n- {notes}"
s = s.replace(marker, entry, 1)
p.write_text(s)
PY

bash ./scripts/checksums.sh generate
bash ./scripts/ci.sh

completed=1
printf '\nVersão preparada: %s -> %s\n' "$old_version" "$new_version"
printf 'Revise CHANGELOG.md e os artefatos em dist/.\n'

if (( commit_release == 1 )); then
    command -v git >/dev/null 2>&1 || { printf 'Git não instalado.\n' >&2; exit 1; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf 'Diretório ainda não é um repositório Git.\n' >&2; exit 1; }
    git add -A
    git commit -m "chore(release): v$new_version"
    git tag -a "v$new_version" -m "SSHPlus Manager v$new_version"
    printf 'Commit e tag locais criados. Envie com:\n'
    printf '  git push origin main\n  git push origin v%s\n' "$new_version"
else
    printf '\nDepois de revisar, execute:\n'
    printf '  git add .\n'
    printf '  git commit -m "chore(release): v%s"\n' "$new_version"
    printf '  git tag -a v%s -m "SSHPlus Manager v%s"\n' "$new_version" "$new_version"
    printf '  git push origin main\n'
    printf '  git push origin v%s\n' "$new_version"
fi
