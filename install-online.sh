#!/usr/bin/env bash
# Instalador online para Releases públicas do SSHPlus Manager.
set -Eeuo pipefail
umask 027

DEFAULT_REPOSITORY='twossh/sshplus-manager-ubuntu'
REPOSITORY="${SSHPLUS_REPOSITORY:-$DEFAULT_REPOSITORY}"
REQUESTED_VERSION="${SSHPLUS_VERSION:-latest}"
SKIP_APT_UPDATE="${SSHPLUS_SKIP_APT_UPDATE:-0}"
CHECKSUMS='SHA256SUMS-release.txt'
INSTALL_ARGS=()

usage() {
    cat <<'USAGE'
Uso:
  curl -fsSL URL/install-online.sh | sudo bash
  curl -fsSL URL/install-online.sh | sudo bash -s -- --version 5.3.0

Opções:
  --version VERSAO       instalar uma Release específica; padrão: latest
  --repository OWNER/REPO usar outro repositório compatível
  --skip-apt-update      não executar apt-get update no bootstrap
  -- ARGS                repassar argumentos adicionais ao install.sh
  -h, --help             exibir esta ajuda

Variáveis equivalentes: SSHPLUS_VERSION, SSHPLUS_REPOSITORY e
SSHPLUS_SKIP_APT_UPDATE=1.
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            shift
            REQUESTED_VERSION="${1:-}"
            ;;
        --repository)
            shift
            REPOSITORY="${1:-}"
            ;;
        --skip-apt-update)
            SKIP_APT_UPDATE=1
            ;;
        --)
            shift
            INSTALL_ARGS+=("$@")
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Opção desconhecida: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

valid_repository() {
    local value="$1" owner name
    [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    owner="${value%%/*}"
    name="${value#*/}"
    [[ "$owner" != . && "$owner" != .. && "$name" != . && "$name" != .. ]] || return 1
    [[ "$owner" != -* && "$name" != -* ]]
}

valid_repository "$REPOSITORY" && [[ "$REPOSITORY" != SEU_USUARIO/* ]] || {
    printf 'Repositório inválido ou não configurado: %s\n' "$REPOSITORY" >&2
    exit 1
}

if [[ "$REQUESTED_VERSION" == latest ]]; then
    ASSET='SSHPlus-Manager-ubuntu-lts-latest.tar.gz'
    RELEASE_BASE="https://github.com/${REPOSITORY}/releases/latest/download"
else
    REQUESTED_VERSION="${REQUESTED_VERSION#v}"
    [[ "$REQUESTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        printf 'Versão inválida: %s\n' "$REQUESTED_VERSION" >&2
        exit 1
    }
    ASSET="SSHPlus-Manager-ubuntu-lts-v${REQUESTED_VERSION}.tar.gz"
    RELEASE_BASE="https://github.com/${REPOSITORY}/releases/download/v${REQUESTED_VERSION}"
fi

if [[ "${SSHPLUS_BOOTSTRAP_TEST_MODE:-0}" == 1 ]]; then
    printf '%s|%s|%s\n' "$REPOSITORY" "$REQUESTED_VERSION" "$ASSET"
    printf '%s\n' "$RELEASE_BASE"
    exit 0
fi

[[ ${EUID:-$(id -u)} -eq 0 ]] || {
    printf 'Execute como root: curl ... | sudo bash\n' >&2
    exit 1
}
[[ -r /etc/os-release ]] || { printf 'Sistema não identificado.\n' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && ( "${VERSION_ID:-}" == 24.04 || "${VERSION_ID:-}" == 26.04 ) ]] || {
    printf 'Este instalador suporta Ubuntu 24.04 LTS e 26.04 LTS. Detectado: %s\n' "${PRETTY_NAME:-desconhecido}" >&2
    exit 1
}

lock_dir='/run/lock/sshplus-online-install.lock.d'
install -d -m 0755 /run/lock
if ! mkdir "$lock_dir" 2>/dev/null; then
    printf 'Outra instalação ou atualização do SSHPlus está em andamento.\n' >&2
    exit 1
fi

work=''
cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    [[ -n "$work" ]] && rm -rf "$work"
    rmdir "$lock_dir" 2>/dev/null || true
    exit "$rc"
}
trap cleanup EXIT INT TERM

export DEBIAN_FRONTEND=noninteractive
apt_options=(-o Acquire::Retries=3 -o DPkg::Lock::Timeout=120)
if [[ "$SKIP_APT_UPDATE" != 1 ]]; then
    apt-get "${apt_options[@]}" update
fi
apt-get "${apt_options[@]}" install -y --no-install-recommends curl ca-certificates tar gzip

work="$(mktemp -d /tmp/sshplus-bootstrap.XXXXXX)"
printf 'Baixando SSHPlus Manager (%s) de %s...\n' "$REQUESTED_VERSION" "$REPOSITORY"
curl -fL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 15 --max-time 300 \
    -o "$work/$ASSET" "$RELEASE_BASE/$ASSET"
curl -fL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 15 --max-time 90 \
    -o "$work/$CHECKSUMS" "$RELEASE_BASE/$CHECKSUMS"

expected="$(awk -v file="$ASSET" '
    NF >= 2 {
        checksum=$1
        name=$2
        sub(/^\*/, "", name)
        sub(/^\.\//, "", name)
        if (name == file) { print checksum; exit }
    }
' "$work/$CHECKSUMS")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || {
    printf 'Checksum esperado não encontrado para %s.\n' "$ASSET" >&2
    exit 1
}
printf '%s  %s\n' "$expected" "$ASSET" > "$work/SHA256SUMS-selected.txt"
(cd "$work" && sha256sum -c --strict SHA256SUMS-selected.txt)

if tar -tzf "$work/$ASSET" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    printf 'Pacote rejeitado: caminho inseguro encontrado no arquivo.\n' >&2
    exit 1
fi
tar -xzf "$work/$ASSET" -C "$work"
source_dir="$work/SSHPlus-Manager-Ubuntu-LTS"
[[ -d "$source_dir" ]] || source_dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'SSHPlus-Manager-Ubuntu-*' -print -quit)"
[[ -n "$source_dir" && -x "$source_dir/install.sh" && -x "$source_dir/verify.sh" && -r "$source_dir/VERSION" ]] || {
    printf 'Pacote inválido ou incompleto.\n' >&2
    exit 1
}

package_version="$(tr -d '\r\n' < "$source_dir/VERSION")"
if [[ "$REQUESTED_VERSION" != latest && "$package_version" != "$REQUESTED_VERSION" ]]; then
    printf 'A Release baixada informa versão %s; esperado %s.\n' "$package_version" "$REQUESTED_VERSION" >&2
    exit 1
fi

NO_COLOR=1 bash "$source_dir/verify.sh"
bash "$source_dir/install.sh" --yes --skip-apt-update "${INSTALL_ARGS[@]}"
printf '\nInstalação concluída: SSHPlus Manager %s. Abra com: sudo menu\n' "$package_version"
