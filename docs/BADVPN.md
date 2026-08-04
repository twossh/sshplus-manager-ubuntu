# BadVPN UDPGW no Ubuntu 24.04/26.04

O módulo usa o release oficial `1.999.130`, commit `752c6b4`, e compila somente o componente `udpgw`.

## Atualização aplicada

- Remove o binário legado `1.999.128` como fonte de instalação.
- Não usa Dropbox, `screen`, `/etc/rc.local` nem `/etc/autostart`.
- Compila localmente com CMake 4 usando `CMAKE_POLICY_VERSION_MINIMUM=3.5`.
- Verifica o commit e a versão do binário antes da instalação.
- Instala em `/usr/local/sbin/badvpn-udpgw`.
- Executa como usuário dinâmico e sem privilégios pelo `systemd`.
- Escuta somente em `127.0.0.1:7300` por padrão.
- Faz backup de qualquer binário anterior em `/var/backups/sshplus/badvpn`.

## Uso

Execute `sudo badvpn` ou abra `sudo menu` e selecione **BadVPN UDPGW**.

A configuração fica em `/etc/sshplus/badvpn.env`.

Por segurança, o gerenciador aceita somente `127.0.0.1` ou `[::1]` como endereço de escuta. O UDPGW foi projetado para ser alcançado por encaminhamento/túnel SSH, não para ficar diretamente exposto à internet.
