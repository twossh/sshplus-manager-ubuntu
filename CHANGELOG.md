# Changelog

Todas as alterações relevantes deste projeto são registradas neste arquivo.

## [Unreleased]

## [5.3.0] - 2026-08-04

### Adicionado

- Pré-verificação do painel público com `sudo sshplus --panel-public preflight --domain DOMINIO`.
- Saída JSON para status e preflight do HTTPS.
- Simulação de renovação com `sudo sshplus --panel-public test-renewal`.
- Instalação online de versão fixada com `--version` ou `SSHPLUS_VERSION`.
- Testes automatizados do seletor de Release e das proteções do instalador online.

### Melhorado

- Ativação HTTPS transacional, com restauração automática da configuração Nginx anterior quando Certbot, TLS ou API falharem.
- Atualização por GitHub com bloqueio contra concorrência, validação da versão interna e rejeição de caminhos inseguros no pacote.
- Release idempotente: reexecuções atualizam os artefatos com `--clobber` sem criar Releases duplicadas.
- Nginx restrito ao único front controller `index.php`; outros arquivos PHP retornam 404.
- Diagnóstico de validade do certificado, DNS, portas 80/443 e resposta local da API via TLS.
- Reparo reaplica automaticamente o template HTTPS quando um domínio público já está ativo.
- Aplicação instalada passa a preservar também `config/` e `systemd/` em `/opt/sshplus`, permitindo reparo completo após atualizações.

### Corrigido

- Evita execuções simultâneas do instalador online, atualizador e gerenciador HTTPS.
- Inclui logs públicos do painel em `tmpfiles.d` e no ciclo normal de manutenção.

## [5.2.1] - 2026-08-04

### Corrigido

- Corrige o teste Nginx do painel HTTPS no GitHub Actions para gravar o log de acesso dentro do diretório temporário do runner.
- Elimina a falha `open() "/var/log/nginx/access.log" failed (13: Permission denied)` durante CI e Release.
- Mantém inalterada a configuração de produção do painel público.


## [5.2.0] - 2026-08-04

### Adicionado

- Publicação opcional do painel em domínio próprio com HTTPS Let's Encrypt.
- Comando `sudo sshplus --panel-public` para ativar, consultar, renovar ou desativar o acesso externo.
- Redirecionamento HTTP→HTTPS, HSTS, TLS 1.2/1.3 e renovação automática por `certbot.timer`.
- Diagnóstico do certificado e do site público no healthcheck.
- Teste isolado da configuração Nginx HTTPS no GitHub Actions.

### Alterado

- O painel local em `127.0.0.1:8088` permanece ativo mesmo quando o domínio público é habilitado.
- O arquivo de credenciais passa a registrar a URL HTTPS quando configurada.

## [5.1.5] - 2026-08-04

### Corrigido

- Move a elevação de privilégio do teste de reparo para o orquestrador de CI.
- Executa somente o teste isolado com `sudo -n`, mantendo as demais validações como usuário do runner.
- Recalcula os checksums após alterações de documentação e elimina falhas causadas por `SHA256SUMS` desatualizado.
- Mantém o reparador de produção restrito ao root.

## [5.1.4] - 2026-08-04

### Corrigido

- Corrige o teste integrado do reparador no GitHub Actions, executando-o com `sudo` não interativo.
- Mantém `sshplus-repair` restrito ao root em produção, sem enfraquecer a validação de segurança.
- Evita a falha falsa `Execute como root` no runner de CI.

## [5.1.3] - 2026-08-04

### Adicionado

- Reparo completo e idempotente com `sudo sshplus --repair`.
- Reconstrução segura da configuração principal, atalhos administrativos e timers `systemd`.
- Teste integrado do reparador em diretórios isolados.

### Corrigido

- Completa instalações interrompidas sem apagar usuários, credenciais ou o banco SQLite.

## [5.1.2] - 2026-08-04

### Adicionado

- Comando `sudo sshplus --panel-repair` e diagnóstico ampliado da API local.
- Teste integrado de login, sessão, agente privilegiado e SQLite.

### Corrigido

- Falhas de auditoria do agente não bloqueiam mais logins válidos.
- Ajusta permissões do painel, `sudoers`, PHP-FPM e arquivos de autenticação.

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
