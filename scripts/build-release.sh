#!/usr/bin/env bash
set -euo pipefail
umask 027

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
TARGET="$(tr -d '\r\n' < "$ROOT/TARGET")"
PROJECT_DIR='SSHPlus-Manager-Ubuntu-LTS'
DIST="$ROOT/dist"
WORK="$(mktemp -d /tmp/sshplus-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'VERSION inválido: %s\n' "$VERSION" >&2; exit 1; }
[[ "$TARGET" == 'ubuntu-lts' ]] || { printf 'TARGET inesperado: %s\n' "$TARGET" >&2; exit 1; }

mkdir -p "$DIST" "$WORK/$PROJECT_DIR"
stage="$WORK/$PROJECT_DIR"

items=(.github api bin config database docs lib modules nginx scripts site sudoers systemd web
       .editorconfig .gitattributes .gitignore CHANGELOG.md CONTRIBUTING.md LICENSE Makefile NOTICE README.md
       REPOSITORY SECURITY.md SUPPORT.md TARGET VERSION install-online.sh install.sh uninstall.sh verify.sh SHA256SUMS)
for item in "${items[@]}"; do
    [[ -e "$ROOT/$item" ]] && cp -a "$ROOT/$item" "$stage/"
done

find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -exec chmod 0644 {} +
find "$stage/bin" -type f -exec chmod 0755 {} +
chmod 0755 "$stage/install-online.sh" "$stage/install.sh" "$stage/uninstall.sh" "$stage/verify.sh" "$stage"/scripts/*.sh

rm -rf "$DIST"/*

package_tree() {
    local dir_name="$1" target_name="$2"
    local zip_name="SSHPlus-Manager-${target_name}-v${VERSION}.zip"
    local tar_name="SSHPlus-Manager-${target_name}-v${VERSION}.tar.gz"
    local latest_zip="SSHPlus-Manager-${target_name}-latest.zip"
    local latest_tar="SSHPlus-Manager-${target_name}-latest.tar.gz"
    (
        cd "$WORK"
        zip -X -q -r "$DIST/$zip_name" "$dir_name"
        tar --sort=name --owner=0 --group=0 --numeric-owner -czf "$DIST/$tar_name" "$dir_name"
    )
    cp -f "$DIST/$zip_name" "$DIST/$latest_zip"
    cp -f "$DIST/$tar_name" "$DIST/$latest_tar"
    unzip -tq "$DIST/$zip_name" >/dev/null
    tar -tzf "$DIST/$tar_name" >/dev/null
}

package_tree "$PROJECT_DIR" 'ubuntu-lts'
cp -a "$stage" "$WORK/SSHPlus-Manager-Ubuntu-24.04"
package_tree 'SSHPlus-Manager-Ubuntu-24.04' 'ubuntu-24.04'
cp -a "$stage" "$WORK/SSHPlus-Manager-Ubuntu-26.04"
package_tree 'SSHPlus-Manager-Ubuntu-26.04' 'ubuntu-26.04'

(
    cd "$DIST"
    sha256sum -- *.zip *.tar.gz | LC_ALL=C sort -k2 > SHA256SUMS-release.txt
)

printf 'Artefatos Ubuntu LTS criados em %s:\n' "$DIST"
find "$DIST" -maxdepth 1 -type f -printf '  %f\n' | LC_ALL=C sort
