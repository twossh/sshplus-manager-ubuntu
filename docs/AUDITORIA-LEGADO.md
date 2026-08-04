# Auditoria resumida do projeto v36-main

A base enviada foi analisada antes da reescrita. Os principais pontos encontrados foram:

- Instalador dependente de Python 2 (`python`, `python-pip`) e scripts incompatíveis com Python 3.
- Instalação do antigo `squid3` a partir do Ubuntu Trusty, com `apt-key` e pacote fixado de 2014.
- Uso intenso de `/etc/init.d`, `service`, `rc.local`, `screen` e cron a cada minuto em vez de unidades `systemd`.
- Substituição completa de `/etc/ssh/sshd_config`, com root por senha, valores extremos de `MaxSessions`/`MaxStartups` e opções obsoletas.
- Downloads de scripts e binários remotos executados sem hash, assinatura ou revisão local.
- Substituição do binário `jq` do sistema por uma versão antiga baixada da internet.
- Limpeza automática de `~/.bash_history`.
- Alterações indevidas em `/etc/hosts` e DNS global.
- Regras de firewall com `iptables -F`, capazes de remover proteções existentes.
- Linha destrutiva no módulo de remoção que poderia executar `rm -rf /bin/` caso um arquivo de controle estivesse ausente.
- Desinstalador removendo pacotes compartilhados do servidor, mesmo quando não instalados exclusivamente pelo sistema.

A versão 4 elimina esses comportamentos e mantém somente componentes administráveis, auditáveis e compatíveis com Ubuntu 26.04.
