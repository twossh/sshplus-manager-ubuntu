# Migração da versão 4.x para 5.0

1. Faça um backup pela versão atual.
2. Mantenha uma sessão SSH administrativa aberta.
3. Execute `sudo ./verify.sh` no pacote 5.0.
4. Execute `sudo ./install.sh`.
5. Confira `/root/sshplus-panel-credentials.txt`.
6. Valide `sudo sshplus --status`.
7. Acesse o painel pelo túnel SSH.

O instalador preserva:

- usuários Linux;
- `/etc/sshplus`;
- `/etc/slowdns/server.key` e `server.pub`;
- perfis em `/root/sshplus-clients`;
- backups existentes;
- banco legado com sufixo `.legacy-*`.

A versão anterior da aplicação é arquivada em
`/var/backups/sshplus/releases` antes da ativação da v5.0.
