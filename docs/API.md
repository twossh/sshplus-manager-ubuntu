# API REST

Base local: `/api`.

## Autenticação

```text
POST /api/login
POST /api/logout
GET  /api/me
```

Requisições de escrita exigem o cabeçalho `X-CSRF-Token` retornado no login.

## Rotas administrativas

```text
GET    /api/status
GET    /api/metrics
GET    /api/users
POST   /api/users
PATCH  /api/users
DELETE /api/users
GET    /api/services
POST   /api/services/restart
GET    /api/audit
GET    /api/backups
POST   /api/backups
GET    /api/updates
POST   /api/updates/apply
GET    /api/rollbacks
POST   /api/rollbacks/apply
GET    /api/servers
POST   /api/servers
DELETE /api/servers
```

## Exemplo de criação de usuário

```json
{
  "username": "cliente01",
  "password": "senha-segura",
  "max_sessions": 1,
  "expires_at": 0,
  "user_type": "normal"
}
```

A API não recebe comandos do sistema, caminhos livres ou unidades `systemd`
fora da lista permitida pelo agente.
