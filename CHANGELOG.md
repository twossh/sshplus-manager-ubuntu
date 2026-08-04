# Changelog

Todas as alterações relevantes deste projeto são registradas neste arquivo.

## [Unreleased]

## [5.1.2] - 2026-08-04

### Corrigido

- O login não retorna mais erro HTTP 500 quando a gravação de auditoria está temporariamente indisponível.
- Comunicação PHP → sudo → agente root com resposta JSON previsível e diagnóstico seguro.
- Permissão direta e por grupo para o usuário `www-data` executar somente o agente autorizado.
- Remoção automática de configurações Nginx duplicadas em `conf.d`.
- Permissões do arquivo de autenticação, sessão PHP e logs do PHP-FPM.

### Adicionado

- Comando `sudo sshplus --panel-repair` para reparar e validar Nginx, PHP-FPM, autenticação e agente.
- Verificações internas em `/api/health` e no diagnóstico pós-instalação.
- Teste obrigatório da ponte privilegiada e da API antes de concluir a instalação.

## [5.1.1] - 2026-08-04

### Corrigido

- Corrige a leitura de `SHA256SUMS-release.txt` quando os nomes possuem o prefixo `./`.
- Gera os checksums da Release sem prefixo de caminho, mantendo compatibilidade com `sha256sum -c`.
- Adiciona teste de regressão para o artefato usado pelo instalador online.


## [5.1.0] - 2026-08-04

### Adicionado

- Suporte oficial ao Ubuntu Server 24.04 LTS, mantendo Ubuntu 26.04 LTS.
- Seleção automática do PHP 8.3 no Ubuntu 24.04 e PHP 8.5 no Ubuntu 26.04.
- Artefatos genéricos `ubuntu-lts` e aliases compatíveis para cada LTS.
- Diagnóstico dinâmico do serviço, socket e binário PHP-FPM.

### Alterado

- Instalador online, atualizador, rollback, painel, API e desinstalador passaram a detectar a plataforma.
- Pacotes principais usam a pasta `SSHPlus-Manager-Ubuntu-LTS`.

## [5.0.2] - 2026-08-04

### Adicionado

- Diagnóstico pós-instalação com `sudo sshplus --healthcheck`.
- Verificação de serviços, timers, SQLite, painel local, API, permissões, BadVPN e SlowDNS.
- Relatório seguro em `/var/log/sshplus`, sem exibir credenciais ou chaves.
- Guia de homologação para a primeira implantação em Ubuntu 24.04/26.04.

## [5.0.1] - 2026-08-04

### Alterado

- Automatiza a primeira Release a partir do envio para a branch main e libera o instalador online sem criação manual de tag.

## [5.0.0] - 2026-08-03

### Adicionado

- Banco SQLite com migração automática da base 4.x.
- Painel web local em Nginx e PHP 8.5 FPM.
- API REST autenticada, proteção CSRF e rate limit de login.
- Agente root com ações permitidas e política sudoers restrita.
- Auditoria, histórico de métricas, inventário de servidores e coleta por systemd.
- Backup registrado no banco e rollback de versões.
- Site estático e workflow GitHub Pages.

### Alterado

- Usuários, expiração e limitador passaram a usar SQLite.
- Instalador e desinstalador reorganizados para a arquitetura v5.
- Painel restrito ao loopback por padrão.
- Banco administrativo isolado do PHP; acesso operacional somente pelo agente root.

## [4.5.0] - 2026-08-03

### Adicionado

- Instalador online baseado na última GitHub Release pública.
- Atualizador integrado ao menu e aos comandos `--check-update` e `--update`.
- Validação SHA-256 antes de instalar uma atualização.
- Arquivo `REPOSITORY` e configurador de proprietário/repositório.
- Artefatos estáveis com nome `latest` para instalação automatizada.
- Documentação de instalação online e atualização.

### Alterado

- Repositório padrão configurado como `twossh/sshplus-manager-ubuntu`.
- Pacotes de Release agora incluem aliases versionados e `latest`.


## [4.4.1] - 2026-08-03

### Adicionado

- Estrutura completa para publicação e manutenção no GitHub.
- GitHub Actions para validação contínua e criação automática de releases.
- Scripts para versionamento semântico, checksums e geração de ZIP/TAR.GZ.
- Templates de issue e pull request, política de segurança e contribuição.
- Documentação passo a passo para publicação e futuras atualizações.

### Alterado

- `VERSION` normalizado para `MAJOR.MINOR.PATCH`.
- Alvo de sistema separado no arquivo `TARGET`.
- Pacote de distribuição preparado de forma reproduzível e validada.

## [4.4.0] - 2026-08-03

### Alterado

- Remoção completa da interface baseada em caixas de diálogo.
- Retorno à interface CLI nativa, sem dependência externa de TUI.
- Nova camada comum para cabeçalhos, mensagens, confirmações, senhas, cores e validações.
- Instalador atômico e otimizações para Ubuntu 24.04/26.04/OpenSSH 10.2p1.
- Inclusão de `tmpfiles.d`, `logrotate` e endurecimento dos serviços systemd.
- Backup e restauração com validação de integridade e caminhos seguros.

## [4.3.0] - 2026-08-03

- Versão baseada em caixas de diálogo, substituída pela CLI 4.4.

## [4.2.0] - 2026-08-03

- DNSTT v1.20260501.0, serviço systemd, chaves persistentes e migração do legado.

## [4.1.0] - 2026-08-03

- BadVPN UDPGW 1.999.130 compilado do código-fonte.
