# Painel web

## Acesso recomendado

O Nginx escuta em `127.0.0.1:8088`. Use túnel SSH:

```bash
ssh -L 8088:127.0.0.1:8088 usuario@IP_DA_VPS
```

Abra `http://127.0.0.1:8088`.

## Credencial inicial

```bash
sudo cat /root/sshplus-panel-credentials.txt
```

Troca pela CLI:

```bash
sudo sshplus --panel-reset-password
```

## Telas

- visão geral com CPU/carga, memória, disco, rede e sessões;
- usuários SSH;
- serviços;
- backups;
- atualização e rollback;
- inventário de servidores;
- auditoria.

## Publicação por HTTPS

O painel permanece local por padrão. Para ativar um domínio com certificado
Let’s Encrypt, use:

```bash
sudo sshplus --panel-public enable \
  --domain painel.exemplo.com \
  --email admin@exemplo.com
```

Consulte [Painel público com domínio e HTTPS](PAINEL-PUBLICO.md). A porta 8088
não deve ser aberta no firewall.

## Isolamento de dados

O PHP não possui acesso ao arquivo `/var/lib/sshplus/sshplus.db`. O banco fica
protegido como `root:root` em modo `0600`; consultas e alterações são realizadas
exclusivamente pelo agente administrativo. A autenticação web utiliza o arquivo
`/etc/sshplus/panel-auth.json`, legível somente por `root` e pelo grupo
`sshplus-api`.

## Diagnóstico e reparo

```bash
sudo sshplus --repair
sudo sshplus --panel-repair
sudo sshplus --healthcheck
curl -fsS http://127.0.0.1:8088/api/health | jq
```

O login não depende da auditoria para ser concluído. Falhas do agente são
registradas em `/var/log/sshplus/php-error.log` com um código de referência, sem
expor senhas ou chaves no navegador.


## Instalação parcial

Se o diagnóstico indicar ausência de `sshplus.conf`, atalhos ou timers, use:

```bash
sudo /opt/sshplus/bin/sshplus-repair
```

O caminho direto funciona mesmo quando `/usr/local/sbin/sshplus` ainda não foi
criado. O reparador não remove usuários nem recria o banco existente.
