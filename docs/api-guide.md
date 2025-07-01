# Guia da API - JuruConnect

Documentação completa das APIs disponíveis no JuruConnect.

## Autenticação

Todas as APIs requerem autenticação via JWT Token.

### Login

```bash
POST /api/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}
```

**Resposta:**
```json
{
  "user": {
    "id": 1,
    "username": "admin",
    "role": "admin"
  },
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

### Headers de Autenticação

```bash
Authorization: Bearer <access_token>
```

## Dashboard APIs

### Métricas do Dashboard

```bash
GET /api/dashboard/metrics
Authorization: Bearer <token>
```

**Resposta:**
```json
{
  "sales": {
    "total": 150000.00,
    "formatted": "R$ 150.000,00"
  },
  "goal": {
    "total": 200000.00,
    "percentage": 75.0
  },
  "stores": [
    {
      "name": "Loja Centro",
      "daily_sales": 15000.00,
      "daily_percentage": 85.5
    }
  ]
}
```

### Performance das Lojas

```bash
GET /api/dashboard/stores/performance
```

## Chat APIs

### Listar Mensagens

```bash
GET /api/chat/messages?chat_id=123&limit=50
```

### Enviar Mensagem

```bash
POST /api/chat/messages
Content-Type: application/json

{
  "chat_id": "123",
  "text": "Mensagem de teste",
  "sender_id": "user123"
}
```

## Códigos de Status

- `200` - Sucesso
- `401` - Não autorizado
- `403` - Acesso negado
- `404` - Não encontrado
- `422` - Dados inválidos
- `500` - Erro interno

## Rate Limiting

- **Login**: 5 tentativas por minuto
- **APIs**: 100 requests por minuto
- **Chat**: 20 mensagens por minuto

## Exemplos com cURL

```bash
# Login
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Dashboard
curl -X GET http://localhost:4000/api/dashboard/metrics \
  -H "Authorization: Bearer <token>"
```
