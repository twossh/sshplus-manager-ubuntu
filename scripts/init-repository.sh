#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
repo="$(tr -d '\r\n[:space:]' < REPOSITORY 2>/dev/null || true)"
default_url=""
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && default_url="https://github.com/${repo}.git"

usage() {
    cat <<USAGE
Uso:
  ./scripts/init-repository.sh [URL_DO_REPOSITORIO] [--push]

Sem URL, usa o valor de REPOSITORY:
  ${default_url:-não configurado}

Exemplo:
  ./scripts/init-repository.sh ${default_url:-https://github.com/usuario/sshplus-manager-ubuntu.git}

A opção --push envia o primeiro commit após preparar o repositório.
USAGE
}

remote_url="$default_url"
push_now=0
while (( $# > 0 )); do
    case "$1" in
        --push) push_now=1 ;;
        -h|--help) usage; exit 0 ;;
        https://github.com/*|git@github.com:*)
            [[ "$remote_url" == "$default_url" ]] || { printf 'Informe apenas uma URL.\n' >&2; exit 2; }
            remote_url="$1"
            ;;
        *) printf 'Opção inválida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

[[ -n "$remote_url" ]] || { usage >&2; exit 2; }
command -v git >/dev/null 2>&1 || { printf 'Git não está instalado.\n' >&2; exit 1; }
[[ "$remote_url" =~ ^(https://github\.com/[^/]+/[^/]+(\.git)?|git@github\.com:[^/]+/[^/]+(\.git)?)$ ]] || {
    printf 'Use uma URL válida de repositório GitHub via HTTPS ou SSH.\n' >&2
    exit 1
}

name="$(git config --global user.name || true)"
email="$(git config --global user.email || true)"
[[ -n "$name" ]] || { printf 'Configure seu nome: git config --global user.name "Seu Nome"\n' >&2; exit 1; }
[[ -n "$email" ]] || { printf 'Configure seu e-mail: git config --global user.email "seu@email"\n' >&2; exit 1; }

if [[ ! -d .git ]]; then
    git init
    git branch -M main
fi

if git remote get-url origin >/dev/null 2>&1; then
    existing="$(git remote get-url origin)"
    [[ "$existing" == "$remote_url" ]] || {
        printf 'O remote origin já aponta para: %s\n' "$existing" >&2
        exit 1
    }
else
    git remote add origin "$remote_url"
fi

git add .
git update-index --chmod=+x install-online.sh install.sh uninstall.sh verify.sh scripts/*.sh bin/*
if git diff --cached --quiet; then
    printf 'Nenhuma alteração nova para o primeiro commit.\n'
else
    git commit -m "feat: publicar SSHPlus Manager v$(cat VERSION)"
fi

printf '\nRepositório local preparado.\n'
printf 'Remote: %s\n' "$remote_url"

if (( push_now == 1 )); then
    git push -u origin main
else
    printf 'Para enviar ao GitHub:\n  git push -u origin main\n'
fi
