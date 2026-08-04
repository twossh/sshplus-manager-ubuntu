# Estratégia multi-servidores

A v5.0 fornece o inventário de servidores e prepara o esquema de dados, mas não
ativa comandos remotos.

A próxima etapa deve incluir:

- TLS obrigatório;
- identidade única por servidor;
- tokens com hash e rotação;
- assinatura e validade temporal de cada solicitação;
- escopos por ação;
- bloqueio por IP;
- fila idempotente;
- auditoria em ambos os lados;
- revogação imediata de agentes.

Não use o cadastro de endpoints como substituto desses controles.
