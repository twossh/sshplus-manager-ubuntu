#!/usr/bin/env bash
set -euo pipefail
umask 027

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
TARGET="$(tr -d '\r\n' < "$ROOT/TARGET")"
PROJECT_DIR='SSHPlus-Manager-Ubuntu-26.04'
DIST="$ROOT/dist"
WORK="$(mktemp -d /tmp/sshplus-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'VERSION inválido: %s\n' "$VERSION" >&2; exit 1; }
[[ "$TARGET" == 'ubuntu-26.04' ]] || { printf 'TARGET inesperado: %s\n' "$TARGET" >&2; exit 1; }

bash "$ROOT/scripts/checksums.sh" check >/dev/null

stage="$WORK/$PROJECT_DIR"
install -d -m 0755 "$stage" "$DIST"

for file in CHANGELOG.md CONTRIBUTING.md LICENSE NOTICE README.md SECURITY.md SUPPORT.md \
            REPOSITORY SHA256SUMS TARGET VERSION install-online.sh install.sh uninstall.sh verify.sh; do
    cp -a "$ROOT/$file" "$stage/"
done
for dir in api bin config database docs lib modules nginx sudoers systemd web; do
    cp -a "$ROOT/$dir" "$stage/"
done

find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -exec chmod 0644 {} +
find "$stage/bin" -type f -exec chmod 0755 {} +
chmod 0755 "$stage/install-online.sh" "$stage/install.sh" "$stage/uninstall.sh" "$stage/verify.sh"

zip_name="SSHPlus-Manager-${TARGET}-v${VERSION}.zip"
tar_name="SSHPlus-Manager-${TARGET}-v${VERSION}.tar.gz"
latest_zip="SSHPlus-Manager-${TARGET}-latest.zip"
latest_tar="SSHPlus-Manager-${TARGET}-latest.tar.gz"
rm -f "$DIST/$zip_name" "$DIST/$tar_name" "$DIST/$latest_zip" "$DIST/$latest_tar" "$DIST/SHA256SUMS-release.txt"

(
    cd "$WORK"
    zip -X -q -r "$DIST/$zip_name" "$PROJECT_DIR"
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf "$DIST/$tar_name" "$PROJECT_DIR"
)
cp -f "$DIST/$zip_name" "$DIST/$latest_zip"
cp -f "$DIST/$tar_name" "$DIST/$latest_tar"

unzip -tq "$DIST/$zip_name" >/dev/null
tar -tzf "$DIST/$tar_name" >/dev/null
(
    cd "$DIST"
    sha256sum "$zip_name" "$tar_name" "$latest_zip" "$latest_tar" > SHA256SUMS-release.txt
)

printf 'Artefatos criados em %s:\n' "$DIST"
printf '  %s\n  %s\n  %s\n  %s\n  SHA256SUMS-release.txt\n' \
    "$zip_name" "$tar_name" "$latest_zip" "$latest_tar"
