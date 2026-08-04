# SSHPlus Manager 5 — Ubuntu 24.04 e 26.04 LTS

Plataforma modular para administrar contas SSH e serviços de túnel em Ubuntu
Server 24.04 e 26.04 LTS. A versão 5 combina CLI, banco SQLite, agente privilegiado,
API REST, painel web local, auditoria, métricas, backup, atualização e rollback.

## Visão geral

- **CLI Bash:** administração direta por `sudo menu`;
- **SQLite:** usuários, auditoria, configurações, métricas e servidores;
- **Agente root:** executa apenas ações previamente permitidas;
- **API REST:** PHP 8.3/8.5 sem framework e sem Composer;
- **Painel web:** Nginx + PHP-FPM, escutando apenas no loopback por padrão;
- **Serviços:** OpenSSH, OpenVPN, BadVPN UDPGW e SlowDNS/DNSTT;
- **Automação:** timers `systemd`, GitHub Actions, Releases e rollback.

## Requisitos

- Ubuntu Server 24.04 LTS ou 26.04 LTS;
- acesso root ou `sudo`;
- `systemd`;
- repositórios oficiais do Ubuntu habilitados;
- acesso à internet para APT e componentes opcionais.

O instalador seleciona `php8.3-fpm` e `php8.3-cli` no Ubuntu 24.04, ou `php8.5-fpm` e `php8.5-cli` no Ubuntu 26.04, além de `nginx` e `sqlite3`.

## Instalação online

Depois de publicar a Release no GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/twossh/sshplus-manager-ubuntu/main/install-online.sh | sudo bash
```

Instalação local:

```bash
chmod +x install.sh verify.sh uninstall.sh
sudo ./verify.sh
sudo ./install.sh
```

Instalação automatizada:

```bash
sudo ./install.sh --yes
```

Definir a credencial inicial:

```bash
sudo ./install.sh \
  --panel-user admin \
  --panel-password 'uma-senha-forte'
```

O painel não pode ser exposto diretamente em IP público pelo instalador v5.0.
O padrão é `127.0.0.1:8088`.

## Acesso ao painel

Na primeira instalação, a credencial é salva com permissão `0600` em:

```text
/root/sshplus-panel-credentials.txt
```

Crie um túnel a partir do seu computador:

```bash
ssh -L 8088:127.0.0.1:8088 usuario@IP_DA_VPS
```

Depois abra:

```text
http://127.0.0.1:8088
```

Comandos úteis:

```bash
sudo sshplus --panel-status
sudo sshplus --panel-reset-password
sudo sshplus --repair
sudo sshplus --healthcheck
```

## Estrutura instalada

| Caminho | Finalidade |
|---|---|
| `/opt/sshplus` | aplicação, API, painel e módulos |
| `/etc/sshplus` | configurações e autenticação protegida do painel |
| `/var/lib/sshplus/sshplus.db` | banco SQLite |
| `/var/log/sshplus` | logs da CLI e do painel |
| `/var/backups/sshplus` | backups e pontos de rollback |
| `/etc/ssh/sshd_config.d/00-sshplus.conf` | configuração modular do OpenSSH |
| `/etc/slowdns/server.key` | chave privada DNSTT |
| `/etc/slowdns/server.pub` | chave pública DNSTT |
| `/root/sshplus-clients` | perfis OpenVPN e dados SlowDNS |

## CLI

```bash
sudo menu
sudo sshplus --status
sudo sshplus --logs
sudo sshplus --version
sudo sshplus --check-update
sudo sshplus --update
sudo badvpn
sudo slowdns
```

## Reparo de instalações incompletas

Se uma atualização for interrompida depois de copiar `/opt/sshplus`, execute:

```bash
sudo /opt/sshplus/bin/sshplus-repair
```

Depois que os atalhos forem reconstruídos, o comando permanente é:

```bash
sudo sshplus --repair
```

O reparador preserva usuários e banco, recria somente arquivos de integração
ausentes, reinstala unidades `systemd`, habilita os timers e valida o painel.

## Segurança da API

O Nginx e o PHP-FPM executam como usuário sem privilégios. Operações
administrativas passam por `/opt/sshplus/bin/sshplus-agent`, chamado pelo
`sudo` com uma política restrita em `/etc/sudoers.d/sshplus-api`.

O agente aceita somente ações cadastradas, valida os parâmetros e registra as
operações na tabela `audit_logs`. O painel usa sessão, cookie `HttpOnly`,
`SameSite=Strict`, proteção CSRF e limitação de tentativas de login no Nginx.
O PHP não abre o banco administrativo: as credenciais ficam em
`/etc/sshplus/panel-auth.json` (`root:sshplus-api`, modo `0640`) e o SQLite
permanece `root:root`, modo `0600`.

## Banco e migração

Na atualização da versão 4.x:

- `/var/lib/sshplus/users.db` é detectado como banco legado;
- uma cópia com sufixo `.legacy-AAAAmmdd-HHMMSS` é preservada;
- os registros válidos são importados para `sshplus.db`;
- `/root/usuarios.db` também pode ser importado;
- usuários Linux e chaves não são recriados nem apagados.

## Atualização e rollback

```bash
sudo sshplus --check-update
sudo sshplus --update
sudo sshplus --repair
sudo sshplus --healthcheck
```

Antes de substituir `/opt/sshplus`, o instalador cria um ponto em:

```text
/var/backups/sshplus/releases/
```

O rollback pode ser executado pelo menu ou painel administrativo.

## Multi-servidores

A v5.0 inclui a tabela `servers`, API e tela para cadastrar endpoints. Nesta
versão, o cadastro é apenas um inventário. O controle remoto entre VPS não é
ativado até que autenticação mútua, rotação de tokens e TLS sejam implementados.

## Desenvolvimento

```bash
make verify
make checksums
make build
```

Documentação:

- [Arquitetura](docs/ARQUITETURA.md)
- [Painel e acesso](docs/PAINEL.md)
- [Homologação pós-instalação](docs/HOMOLOGACAO.md)
- [API REST](docs/API.md)
- [Migração para v5](docs/MIGRACAO-V5.md)
- [Estratégia multi-servidores](docs/MULTISSERVIDOR.md)
- [GitHub](docs/GITHUB.md)
- [Versionamento](docs/VERSIONAMENTO.md)

## Desinstalação

Preservando dados:

```bash
sudo ./uninstall.sh
```

Remoção completa dos dados do SSHPlus:

```bash
sudo ./uninstall.sh --purge-data
```

Os usuários Linux gerenciados são preservados nos dois modos.
