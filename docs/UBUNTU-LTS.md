# Compatibilidade com Ubuntu LTS

O SSHPlus Manager 5.1 suporta oficialmente:

- Ubuntu Server 24.04 LTS (Noble Numbat), com PHP 8.3;
- Ubuntu Server 26.04 LTS (Resolute Raccoon), com PHP 8.5.

O instalador lê `/etc/os-release`, rejeita outras versões e seleciona automaticamente:

| Ubuntu | PHP CLI | PHP-FPM | Socket | Serviço |
|---|---|---|---|---|
| 24.04 | `php8.3-cli` | `php8.3-fpm` | `/run/php/php8.3-fpm.sock` | `php8.3-fpm.service` |
| 26.04 | `php8.5-cli` | `php8.5-fpm` | `/run/php/php8.5-fpm.sock` | `php8.5-fpm.service` |

O OpenSSH é configurado por `/etc/ssh/sshd_config.d/00-sshplus.conf` com diretivas compatíveis com as duas versões. Antes de reiniciar o serviço, o instalador executa `sshd -t`.

## Atualização da v5.0.2

A Release mantém artefatos de compatibilidade com o nome `ubuntu-26.04` e a pasta interna antiga. Assim, o atualizador da v5.0.2 em Ubuntu 26.04 consegue instalar a v5.1.0 normalmente.
