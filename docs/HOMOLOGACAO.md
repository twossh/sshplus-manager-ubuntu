# Homologação pós-instalação

A partir da versão 5.0.2, o SSHPlus inclui um diagnóstico somente leitura para
confirmar se a instalação está adequada antes do uso em produção.

## Executar

```bash
sudo sshplus --healthcheck
```

Também está disponível no menu principal em **Diagnóstico e homologação**.

## Verificações

O diagnóstico confere:

- Ubuntu 24.04/26.04 e arquitetura;
- versão e arquivos essenciais;
- atalhos instalados em `/usr/local`;
- sintaxe e estado do OpenSSH;
- timers de expiração, limite e métricas;
- proprietário, permissão, integridade e tabelas do SQLite;
- Nginx, PHP-FPM, autenticação e API local do painel;
- restrição do painel ao endereço de loopback;
- BadVPN e SlowDNS quando instalados;
- presença e permissão das chaves DNSTT;
- unidades `systemd` em estado de falha.

O comando não imprime senhas, hashes, chaves privadas nem conteúdo do banco.
Quando executado como root, grava o resultado em:

```text
/var/log/sshplus/healthcheck-AAAAMMDD-HHMMSS.log
```

## Resultado esperado

Avisos são aceitáveis para módulos opcionais ainda não instalados. O servidor
está aprovado quando o relatório termina com zero erros.

```text
Resultado: N aprovado(s), N aviso(s), 0 erro(s).
```

Use uma VPS descartável na primeira homologação e mantenha o console da
hospedagem disponível durante alterações no OpenSSH e firewall.


## Correção automática

Quando o diagnóstico encontrar arquivos de integração, atalhos ou timers
ausentes, execute:

```bash
sudo /opt/sshplus/bin/sshplus-repair
sudo sshplus --healthcheck
```
