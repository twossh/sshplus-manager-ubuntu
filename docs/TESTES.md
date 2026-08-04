# Testes e validações

Execute:

```bash
chmod +x verify.sh
sudo ./verify.sh
```

O verificador cobre:

- Sintaxe Bash de todos os scripts.
- Arquivos obrigatórios.
- Finais de linha CRLF.
- Arquivos graváveis por qualquer usuário.
- Ausência de dependências TUI e técnicas legadas.
- Compatibilidade do ambiente com Ubuntu 24.04/26.04.
- Estrutura das unidades `systemd`.
- Inclusão, leitura e remoção atômicas no banco de usuários.
- Validação da configuração OpenSSH atual, quando executado como root.
- Timers instalados.
- Versões instaladas de BadVPN e DNSTT.
- Presença das chaves `server.key` e `server.pub`.
- Seleção da Release latest ou de versão fixada no instalador online.
- Template Nginx HTTPS, front controller PHP e rollback transacional.
- Pacotes de Release e checksums usados pelo instalador online.

## Teste recomendado em VPS

1. Criar snapshot da VPS.
2. Manter uma sessão SSH aberta.
3. Executar `sudo ./verify.sh`.
4. Executar `sudo ./install.sh`.
5. Abrir uma segunda conexão SSH.
6. Criar um usuário temporário.
7. Testar expiração e limite de sessões.
8. Instalar BadVPN e SlowDNS separadamente.
9. Reiniciar a VPS e conferir todos os serviços.
