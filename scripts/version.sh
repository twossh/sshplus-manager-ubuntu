#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"

usage() {
    cat <<'USAGE'
Uso:
  ./scripts/version.sh show
  ./scripts/version.sh bump patch|minor|major
  ./scripts/version.sh set X.Y.Z
USAGE
}

valid_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

current="$(tr -d '\r\n' < "$VERSION_FILE")"
valid_version "$current" || { printf 'Versão inválida em VERSION: %s\n' "$current" >&2; exit 1; }

command="${1:-show}"
case "$command" in
    show)
        printf '%s\n' "$current"
        ;;
    set)
        next="${2:-}"
        valid_version "$next" || { usage >&2; exit 2; }
        printf '%s\n' "$next" > "$VERSION_FILE"
        printf '%s -> %s\n' "$current" "$next"
        ;;
    bump)
        part="${2:-}"
        IFS=. read -r major minor patch <<< "$current"
        case "$part" in
            patch) patch=$((patch + 1)) ;;
            minor) minor=$((minor + 1)); patch=0 ;;
            major) major=$((major + 1)); minor=0; patch=0 ;;
            *) usage >&2; exit 2 ;;
        esac
        next="$major.$minor.$patch"
        printf '%s\n' "$next" > "$VERSION_FILE"
        printf '%s -> %s\n' "$current" "$next"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
