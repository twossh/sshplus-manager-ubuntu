# Painel público com domínio e HTTPS

O SSHPlus mantém o painel local em `127.0.0.1:8088`. A publicação na internet é
opcional e cria um segundo acesso protegido por HTTPS, sem remover o túnel SSH.

## Pré-requisitos

- Ubuntu 24.04 ou 26.04 LTS;
- domínio próprio, por exemplo `painel.exemplo.com`;
- registro DNS tipo `A` apontando para o IPv4 público da VPS;
- portas TCP 80 e 443 liberadas no firewall do provedor;
- endereço de e-mail válido para avisos do Let's Encrypt.

## Ativação

```bash
sudo sshplus --panel-public enable \
  --domain painel.exemplo.com \
  --email admin@exemplo.com
```

O comando:

1. confirma o DNS;
2. repara e valida o painel local;
3. instala o Certbot pelos repositórios do Ubuntu;
4. solicita um certificado Let's Encrypt por desafio HTTP;
5. configura redirecionamento HTTP para HTTPS;
6. ativa HSTS e cabeçalhos de segurança;
7. habilita `certbot.timer` para renovação automática;
8. mantém o acesso local e o túnel SSH disponíveis.

Caso o domínio use proxy reverso ou CDN e o DNS não mostre diretamente o IP da
VPS, revise a configuração e, somente quando souber que o tráfego chega à VPS,
use `--force`.

## Estado

```bash
sudo sshplus --panel-public status
```

## Renovação

```bash
sudo sshplus --panel-public renew
```

O pacote Certbot também executa renovações automáticas pelo `systemd`.

## Desativação

```bash
sudo sshplus --panel-public disable
```

O certificado é preservado para facilitar uma futura reativação. Para remover
também o certificado:

```bash
sudo sshplus --panel-public disable --purge-certificate
```

A desativação não remove regras 80/443 do firewall, porque essas portas podem
ser utilizadas por outros sites no mesmo servidor.

## Segurança

- O painel local continua limitado ao loopback.
- O acesso público aceita apenas TLS 1.2 e TLS 1.3.
- Cookies de sessão recebem a marca `Secure` quando o acesso ocorre por HTTPS.
- Login continua protegido por rate limit, sessão `HttpOnly`, `SameSite=Strict`
  e CSRF.
- A API PHP não recebe acesso direto ao banco administrativo.
