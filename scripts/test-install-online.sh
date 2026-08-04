#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install-online.sh"

latest="$(SSHPLUS_BOOTSTRAP_TEST_MODE=1 bash "$INSTALLER")"
grep -Fxq 'twossh/sshplus-manager-ubuntu|latest|SSHPlus-Manager-ubuntu-lts-latest.tar.gz' <<< "$latest"
grep -Fxq 'https://github.com/twossh/sshplus-manager-ubuntu/releases/latest/download' <<< "$latest"

pinned="$(SSHPLUS_BOOTSTRAP_TEST_MODE=1 bash "$INSTALLER" --version 5.3.0)"
grep -Fxq 'twossh/sshplus-manager-ubuntu|5.3.0|SSHPlus-Manager-ubuntu-lts-v5.3.0.tar.gz' <<< "$pinned"
grep -Fxq 'https://github.com/twossh/sshplus-manager-ubuntu/releases/download/v5.3.0' <<< "$pinned"

custom="$(SSHPLUS_BOOTSTRAP_TEST_MODE=1 bash "$INSTALLER" --repository example/project --version v1.2.3)"
grep -Fxq 'example/project|1.2.3|SSHPlus-Manager-ubuntu-lts-v1.2.3.tar.gz' <<< "$custom"

if SSHPLUS_BOOTSTRAP_TEST_MODE=1 bash "$INSTALLER" --version invalida >/dev/null 2>&1; then
    printf 'O instalador aceitou uma versão inválida.\n' >&2
    exit 1
fi
if SSHPLUS_BOOTSTRAP_TEST_MODE=1 bash "$INSTALLER" --repository '../repo' >/dev/null 2>&1; then
    printf 'O instalador aceitou um repositório inválido.\n' >&2
    exit 1
fi

grep -q 'tar -tzf' "$INSTALLER"
grep -q 'Pacote rejeitado: caminho inseguro' "$INSTALLER"

echo 'Instalador online: seleção de Release e validações aprovadas.'
