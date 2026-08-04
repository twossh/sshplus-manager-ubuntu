# Política de segurança

## Versões suportadas

Somente a versão estável mais recente recebe correções de segurança. Faça a
atualização antes de relatar um problema já corrigido em release posterior.

## Como relatar uma vulnerabilidade

Não publique senhas, chaves privadas, tokens, endereços administrativos ou
passos de exploração completos em uma issue pública.

Use o recurso **Private vulnerability reporting** do GitHub quando ele estiver
habilitado. Caso não esteja disponível, abra uma issue sem detalhes sensíveis,
marcada como solicitação de contato de segurança, para que o mantenedor defina
um canal privado.

Inclua no relato privado:

- versão do SSHPlus Manager;
- versão do Ubuntu;
- componente afetado;
- impacto esperado;
- passos mínimos para reprodução;
- correção sugerida, quando houver.

## Escopo

São relevantes vulnerabilidades nos scripts do projeto, permissões,
configurações OpenSSH, serviços systemd, validação de entradas, backups e
processos de instalação. Problemas nos projetos upstream BadVPN e DNSTT devem
também ser comunicados aos respectivos mantenedores.
