# Publicação no GitHub

## 1. Criar o repositório no site

1. Entre no GitHub e selecione **New repository**.
2. Use um nome como `sshplus-manager-ubuntu`.
3. Escolha **Public** para permitir instalação e atualização automáticas sem token. Use **Private** somente se também adaptar autenticação dos downloads.
4. Não marque as opções para criar README, `.gitignore` ou licença, pois esses
   arquivos já existem no projeto.
5. Crie o repositório vazio.

## Método assistido pelo projeto

Depois de criar um repositório vazio no GitHub e configurar seu nome e e-mail,
você pode preparar o primeiro commit com:

```bash
bash ./scripts/init-repository.sh
```

Revise o resultado e envie:

```bash
git push -u origin main
```

Para preparar e enviar em uma única execução:

```bash
bash ./scripts/init-repository.sh --push
```

## 2. Preparar o Git no computador

Abra o Git Bash, PowerShell ou terminal dentro da pasta extraída:

```bash
git init
git branch -M main
git config user.name "SEU NOME"
git config user.email "SEU EMAIL DO GITHUB"
git add .
git update-index --chmod=+x install.sh uninstall.sh verify.sh scripts/*.sh bin/*
git commit -m "feat: publicar SSHPlus Manager v5.0.0"
```

## 3. Ligar ao repositório remoto

O repositório já está configurado como `twossh/sshplus-manager-ubuntu`:

```bash
git remote add origin https://github.com/twossh/sshplus-manager-ubuntu.git
git push -u origin main
```

O comando `git update-index --chmod=+x` é importante quando o primeiro commit
é feito no Windows, pois registra os scripts como executáveis no repositório.

O GitHub solicitará autenticação. Em HTTPS, use o navegador, Git Credential
Manager ou um token; não use a senha comum da conta como senha Git.

## Alternativa com GitHub CLI

Depois de executar `git init`, `git add` e `git commit`:

```bash
gh auth login
gh repo create sshplus-manager-ubuntu --private --source=. --remote=origin --push
```

Troque `--private` por `--public` quando desejar publicação aberta.

## 4. Conferir o GitHub Actions

Abra a aba **Actions**. O workflow **CI** deve executar automaticamente. Ele
valida sintaxe, ShellCheck, checksums, serviços e pacote de distribuição.

Se a criação de uma release retornar erro de permissão, abra:

```text
Settings → Actions → General → Workflow permissions
```

Permita leitura e escrita para workflows ou confirme que o workflow pode usar
`contents: write`.

## 5. Publicar a primeira release

A versão atual é lida de `VERSION`:

```bash
cat VERSION
git tag -a v5.0.0 -m "SSHPlus Manager v5.0.0"
git push origin v5.0.0
```

O workflow **Release** criará automaticamente:

- ZIP de instalação;
- TAR.GZ de instalação;
- checksums SHA-256;
- notas automáticas da versão.

## 6. Atualizações futuras

Faça as alterações em uma branch:

```bash
git switch -c feat/nome-da-melhoria
```

Valide e envie:

```bash
make verify
git add .
git commit -m "feat: descreva a melhoria"
git push -u origin feat/nome-da-melhoria
```

Abra um Pull Request para `main`. Depois de aprovado e incorporado, prepare a
nova versão seguindo `docs/VERSIONAMENTO.md`.

## 7. Instalação e atualização pela Release

Depois da primeira Release, uma VPS Ubuntu 24.04/26.04 poderá instalar o sistema com:

```bash
curl -fsSL https://raw.githubusercontent.com/twossh/sshplus-manager-ubuntu/main/install-online.sh | sudo bash
```

Uma instalação existente poderá verificar e aplicar atualizações com:

```bash
sudo sshplus --check-update
sudo sshplus --update
```

O atualizador baixa apenas a Release publicada, valida o arquivo de checksums e
executa a verificação do pacote antes da instalação.
