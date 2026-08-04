#!/usr/bin/env bash
# Instalador online para Releases públicas do SSHPlus Manager.
set -euo pipefail
umask 027

DEFAULT_REPOSITORY='twossh/sshplus-manager-ubuntu'
REPOSITORY="${SSHPLUS_REPOSITORY:-$DEFAULT_REPOSITORY}"
ASSET='SSHPlus-Manager-ubuntu-lts-latest.tar.gz'
CHECKSUMS='SHA256SUMS-release.txt'

[[ ${EUID:-$(id -u)} -eq 0 ]] || { printf 'Execute como root: curl ... | sudo bash\n' >&2; exit 1; }
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$REPOSITORY" != SEU_USUARIO/* ]] || {
    printf 'Repositório não configurado no install-online.sh.\n' >&2
    printf 'No projeto, execute: scripts/configure-repository.sh usuario/repositorio\n' >&2
    exit 1
}
[[ -r /etc/os-release ]] || { printf 'Sistema não identificado.\n' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && ( "${VERSION_ID:-}" == 24.04 || "${VERSION_ID:-}" == 26.04 ) ]] || {
    printf 'Este instalador suporta Ubuntu 24.04 LTS e 26.04 LTS. Detectado: %s\n' "${PRETTY_NAME:-desconhecido}" >&2
    exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y --no-install-recommends curl ca-certificates tar gzip

work="$(mktemp -d /tmp/sshplus-bootstrap.XXXXXX)"
trap 'rm -rf "$work"' EXIT
base="https://github.com/${REPOSITORY}/releases/latest/download"
printf 'Baixando a última Release de %s...\n' "$REPOSITORY"
curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300 -o "$work/$ASSET" "$base/$ASSET"
curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 -o "$work/$CHECKSUMS" "$base/$CHECKSUMS"
expected="$(awk -v file="$ASSET" '
    NF >= 2 {
        checksum=$1
        name=$2
        sub(/^\*/, "", name)
        sub(/^\.\//, "", name)
        if (name == file) { print checksum; exit }
    }
' "$work/$CHECKSUMS")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { printf 'Checksum esperado não encontrado.\n' >&2; exit 1; }
printf '%s  %s\n' "$expected" "$ASSET" > "$work/SHA256SUMS-selected.txt"
(cd "$work" && sha256sum -c --strict SHA256SUMS-selected.txt)
tar -xzf "$work/$ASSET" -C "$work"
source_dir="$work/SSHPlus-Manager-Ubuntu-LTS"
[[ -d "$source_dir" ]] || source_dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'SSHPlus-Manager-Ubuntu-*' -print -quit)"
[[ -x "$source_dir/install.sh" && -x "$source_dir/verify.sh" ]] || { printf 'Pacote inválido.\n' >&2; exit 1; }
NO_COLOR=1 bash "$source_dir/verify.sh"
bash "$source_dir/install.sh" --yes --skip-apt-update
printf '\nInstalação concluída. Abra com: sudo menu\n'
