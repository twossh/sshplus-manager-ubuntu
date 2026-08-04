# Migração da versão 36

1. Faça backup da VPS ou snapshot do provedor.
2. Mantenha `/root/usuarios.db`; o instalador importa `usuario limite` automaticamente.
3. Execute `sudo ./install.sh` em Ubuntu 26.04 LTS.
4. Verifique os usuários em `sudo menu` → Gerenciar usuários → Listar.
5. Teste uma segunda conexão SSH antes de encerrar a sessão atual.
6. Recrie clientes OpenVPN no novo menu. Certificados antigos não são importados automaticamente.

O instalador guarda cópias em `/var/backups/sshplus/install/<data-hora>`.
