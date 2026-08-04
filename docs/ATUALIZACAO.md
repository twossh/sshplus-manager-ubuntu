# Instalação online e atualização

## Configurar o repositório antes do primeiro push

Execute uma única vez, trocando pelo endereço real:

```bash
bash scripts/configure-repository.sh twossh/sshplus-manager-ubuntu
make checksums
make verify
```

Isso grava o endereço em `REPOSITORY` e atualiza o instalador online e a documentação.

## Instalação por um comando

Disponível para repositórios públicos depois que a primeira Release for publicada:

```bash
curl -fsSL https://raw.githubusercontent.com/twossh/sshplus-manager-ubuntu/main/install-online.sh | sudo bash
```

Para revisar o instalador antes de executar:

```bash
curl -fLO https://raw.githubusercontent.com/twossh/sshplus-manager-ubuntu/main/install-online.sh
less install-online.sh
sudo bash install-online.sh
```

## Atualização na VPS

Pelo menu:

```bash
sudo menu
```

Escolha **Atualizações do sistema**.

Pela linha de comando:

```bash
sudo sshplus --check-update
sudo sshplus --update
```

O atualizador consulta a última GitHub Release, baixa o `tar.gz`, valida o SHA-256,
executa `verify.sh` e só então chama o instalador. A atualização normal preserva
configurações, banco de usuários, logs, backups e chaves do SlowDNS.

## Repositório privado

O instalador online e o atualizador integrado foram projetados para Releases
públicas. Para repositório privado, baixe manualmente o artefato autenticado no
GitHub e execute `verify.sh` e `install.sh` localmente, sem colocar tokens em
scripts ou URLs.
