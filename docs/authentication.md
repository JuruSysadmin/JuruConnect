# Sistema de Autenticação

O JuruConnect usa um sistema de autenticação robusto baseado em JWT.

## Componentes de Segurança

### 1. Guardian JWT
- **Access tokens** com expiração de 1 hora
- **Refresh tokens** com expiração de 7 dias
- **Revogação** de tokens comprometidos

### 2. Rate Limiting
- **5 tentativas** de login por minuto por IP
- **Bloqueio automático** após múltiplas falhas
- **Whitelist** para IPs confiáveis

### 3. Logs de Segurança
- **Tentativas de login** (sucessos e falhas)
- **Mudanças de senha**
- **Atividades suspeitas**
- **Bloqueios automáticos**

## Configuração

### Variáveis de Ambiente

```bash
# .env
GUARDIAN_SECRET_KEY=your-256-bit-secret
GUARDIAN_ISSUER=JuruConnect
RATE_LIMIT_LOGIN_ATTEMPTS=5
RATE_LIMIT_WINDOW_MINUTES=1
```

### Políticas de Senha

```elixir
# config/config.exs
config :app, App.Auth.PasswordPolicy,
  min_length: 8,
  max_length: 128,
  min_uppercase: 1,
  min_digits: 1,
  require_special_chars: true,
  password_expiry_days: 90
```

## Fluxo de Autenticação

### 1. Login
```
User → Login Form → Rate Limiter → Authentication → Token Generation
```

### 2. Token Refresh
```
Client → Refresh Token → Validation → New Access Token
```

### 3. Logout
```
Client → Logout Request → Token Revocation → Session Cleanup
```

## Monitoramento de Segurança

### Dashboard Admin
- **Tentativas de login** por período
- **IPs bloqueados**
- **Contas suspensas**
- **Relatórios de segurança**

### Alertas Automáticos
- **Brute force** detectado
- **Login suspeito** (novo IP)
- **Múltiplas falhas** de autenticação
