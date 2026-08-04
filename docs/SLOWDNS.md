# SlowDNS atualizado — DNSTT v1.20260501.0

O módulo usa o projeto oficial DNSTT, que implementa um túnel DNS autenticado e criptografado. A versão é fixada em `v1.20260501.0` e os binários são compilados no próprio servidor com Go.

## Migração da versão antiga

Quando `/etc/SSHPlus/dns` existe, o instalador cria um backup em `/var/backups/sshplus/slowdns`, reaproveita o par de chaves quando válido, tenta importar a zona e a porta TCP do arquivo `autodns` e encerra somente o processo legado cujo caminho é `/etc/SSHPlus/dns/dns-server`.

## Instalação

Após instalar o SSHPlus Manager:

```bash
sudo slowdns
```

Escolha `1) Instalar ou atualizar` e depois `2) Configurar domínio, porta e destino`.

## DNS do domínio

Use uma subzona exclusiva para o túnel. Exemplo:

- Servidor VPS: `203.0.113.10`
- Host do nameserver: `ns1.exemplo.com`
- Zona do túnel: `t.exemplo.com`

No provedor DNS:

1. Crie `A ns1.exemplo.com -> 203.0.113.10`.
2. Delegue `t.exemplo.com` com `NS ns1.exemplo.com`.
3. Desative proxy/CDN no registro A do nameserver.

A propagação DNS pode levar algum tempo. O módulo não altera automaticamente os registros do seu provedor.

## Porta 53

O padrão recomendado é vincular o DNSTT ao IPv4 da interface do servidor na porta UDP 53. Isso evita substituir o `systemd-resolved`, que normalmente usa apenas endereços de loopback.

Caso a porta 53 já esteja ocupada no mesmo endereço, identifique o conflito antes de iniciar:

```bash
sudo ss -lunp | grep ':53 '
```

## Destino local

O DNSTT encaminha conexões para um serviço TCP local. O padrão é o OpenSSH:

```text
127.0.0.1:22
```

Também é possível indicar outra porta TCP local administrada por você. Destinos externos são rejeitados pelo módulo.

## Cliente

As informações são exportadas para:

```text
/root/sshplus-clients/slowdns-info.txt
```

O pacote instala também `dnstt-client` para testes Linux. Exemplo:

```bash
dnstt-client -udp 1.1.1.1:53 -pubkey CHAVE_PUBLICA t.exemplo.com 127.0.0.1:2222
ssh -p 2222 usuario@127.0.0.1
```

## Segurança

- Serviço executado com usuário dedicado sem shell.
- A única capacidade concedida é `CAP_NET_BIND_SERVICE`.
- Chave privada em `/etc/slowdns/server.key`, acessível somente por root e pelo grupo do serviço.
- Configuração validada antes do início.
- Compilação usa Go Module Proxy e SumDB para validar a integridade do módulo.
- Nenhum binário pré-compilado de repositórios de terceiros é usado.

Use o recurso somente em infraestrutura própria ou com autorização explícita.
