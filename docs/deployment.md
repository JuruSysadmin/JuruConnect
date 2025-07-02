# Deploy em Produção

Guia para colocar o JuruConnect em produção.

## Preparação

### 1. Variáveis de Ambiente

```bash
# .env.prod
MIX_ENV=prod
SECRET_KEY_BASE=your-secret-key-base
DATABASE_URL=postgresql://user:pass@host:5432/juruconnect_prod
GUARDIAN_SECRET_KEY=your-guardian-secret
API_BASE_URL=https://api.jurunense.com
PHX_HOST=juruconnect.com.br
```

### 2. Build de Produção

```bash
# Compile assets
MIX_ENV=prod mix assets.deploy

# Compile aplicação
MIX_ENV=prod mix compile

# Gerar release
MIX_ENV=prod mix release
```

## Deploy com Docker

### Dockerfile

```dockerfile
FROM elixir:1.14-alpine AS build

RUN apk add --no-cache build-base npm git python3

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY assets/package*.json assets/
RUN npm install --prefix assets

COPY . .
RUN mix assets.deploy
RUN mix release

FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel/app ./

EXPOSE 4000

CMD ["./bin/app", "start"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/juruconnect_prod
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: juruconnect_prod
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Deploy Manual

### 1. Servidor

```bash
# No servidor de produção
git clone https://github.com/jurunense/juruconnect.git
cd juruconnect

# Instalar dependências
mix deps.get --only prod

# Configurar banco
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate

# Build e iniciar
MIX_ENV=prod mix phx.server
```

### 2. Nginx (Proxy)

```nginx
server {
    listen 80;
    server_name juruconnect.com.br;

    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Monitoramento

### Health Check

```bash
# Endpoint de saúde
curl http://localhost:4000/health
```

### Logs

```bash
# Logs da aplicação
tail -f _build/prod/rel/app/log/erlang.log

# Logs do sistema
journalctl -u juruconnect -f
```

## Backup

### Banco de Dados

```bash
# Backup
pg_dump juruconnect_prod > backup_$(date +%Y%m%d).sql

# Restore
psql juruconnect_prod < backup_20241201.sql
```

## SSL/HTTPS

### Let's Encrypt

```bash
# Instalar certbot
sudo apt install certbot python3-certbot-nginx

# Gerar certificado
sudo certbot --nginx -d juruconnect.com.br
```
