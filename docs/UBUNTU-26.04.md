# Compatibilidade com Ubuntu 26.04 LTS

## OpenSSH

- Configuração modular em `/etc/ssh/sshd_config.d/00-sshplus.conf`.
- Validação obrigatória com `/usr/sbin/sshd -t`.
- Reinício apenas depois de uma validação bem-sucedida.
- Root por senha não é habilitado.
- Compatibilidade com OpenSSH 10.2p1.

## Serviços

Todos os processos persistentes usam unidades `systemd`:

- `sshplus-expirer.timer`
- `sshplus-limiter.timer`
- `sshplus-badvpn.service`
- `sshplus-slowdns.service`
- `sshplus-openvpn-nat.service`, quando OpenVPN é instalado

## Rede

- UFW é configurado sem ser ativado automaticamente pelo instalador.
- Fail2ban usa o backend `systemd`.
- OpenVPN utiliza nftables para NAT.
- BadVPN escuta somente em loopback.
- SlowDNS aceita destino TCP somente em `127.0.0.1`.

## Arquivos de sistema

- `/etc/tmpfiles.d/sshplus.conf` recria diretórios e permissões.
- `/etc/logrotate.d/sshplus` controla a rotação dos logs.
- Nenhum uso de `rc.local`, SysV init ou `screen`.
