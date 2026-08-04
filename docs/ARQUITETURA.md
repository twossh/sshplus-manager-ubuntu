# Arquitetura da versão 5

## Camadas

```text
Navegador
  └─ Nginx 127.0.0.1:8088
      └─ PHP 8.5 FPM
          ├─ autenticação em arquivo protegido
          └─ sudo restrito
              └─ sshplus-agent (root)
                  ├─ contas Linux/OpenSSH
                  ├─ systemd
                  ├─ backups
                  ├─ atualização/rollback
                  └─ SQLite + auditoria
```

O painel não executa comandos de shell fornecidos pelo usuário. Cada chamada é
mapeada para uma ação fechada no agente. Unidades `systemd`, nomes de usuário,
portas, datas e caminhos são validados antes do uso.

## Diretórios do repositório

```text
api/        API REST em PHP
bin/        executáveis CLI e agente
config/     drop-ins de serviços
database/  esquema e migrações SQLite
docs/       documentação
lib/        funções compartilhadas e serviços de domínio
modules/    menus e módulos CLI
nginx/      template do virtual host
site/       site estático para GitHub Pages
sudoers/    política restrita do agente
systemd/    serviços e timers
web/        frontend administrativo
```

## Princípios

1. privilégios mínimos;
2. painel local por padrão;
3. banco transacional;
4. atualização atômica;
5. rollback antes de substituir código;
6. auditoria de ações administrativas;
7. nenhuma dependência de `dialog`, `screen`, `rc.local` ou Python 2.

## Separação de privilégios do painel

O PHP não abre o banco administrativo. A autenticação web é lida de `/etc/sshplus/panel-auth.json`, protegido por `root:sshplus-api` e modo `0640`. Toda consulta ou alteração operacional passa pelo `sshplus-agent`, executado por uma regra `sudoers` restrita. O banco `/var/lib/sshplus/sshplus.db` permanece `root:root` com modo `0600`.

