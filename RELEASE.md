# Manual de Release - JuruConnect

Este documento explica como gerar uma release de produção e executá-la.

## Pré-requisitos

- Elixir 1.19+
- Mix
- Node.js 18+
- PostgreSQL
- MinIO

## Gerando uma Release

### 1. Preparar dependências de produção

```bash
MIX_ENV=prod mix deps.get --only prod
```

### 2. Compilar em ambiente de produção

```bash
MIX_ENV=prod mix compile
```

### 3. Deploy dos assets estáticos

```bash
MIX_ENV=prod mix assets.deploy
```

Este comando:
- Compila CSS e JavaScript
- Aplica digest para cache busting
- Otimiza assets para produção

### 4. Gerar a release

```bash
MIX_ENV=prod mix release
```

A release será criada na pasta `_build/prod/rel/app/`

## Executando a Release

### Modo de desenvolvimento local

```bash
# Compilar
mix deps.get
mix compile
mix assets.deploy

# Executar servidor de desenvolvimento
mix phx.server
```

### Modo de produção com release

```bash
# Usando a release gerada
_build/prod/rel/app/bin/app start
```

### Executar migrações do banco de dados

**Para desenvolvimento:**
```bash
mix ecto.migrate
```

**Para produção (usando release):**
```bash
_build/prod/rel/app/bin/app eval "App.Release.migrate()"
```

### Configuração do banco de dados para produção

Defina as seguintes variáveis de ambiente:

```bash
export DATABASE_URL="ecto://username:password@host/database_name"
export SECRET_KEY_BASE="sua_chave_secreta_aqui"
export PHX_HOST="seu_dominio.com"
```

### Criando dados iniciais do banco

```bash
# Para desenvolvimento
mix run priv/repo/seeds.exs

# Para produção
_build/prod/rel/app/bin/app eval "App.Release.seed()"
```

## Scripts Úteis

### Script de setup do MinIO

```bash
./scripts/setup_minio.sh
```

Este script:
- Configura bucket `juruconnect`
- Define política de acesso público
- Verifica conectividade

### Docker Compose para serviços auxiliares

```bash
# PostgreSQL + MinIO
docker-compose up -d
```

## Variáveis de Ambiente Obrigatórias

### Desenvolvimento
- `DATABASE_URL`
- `SECRET_KEY_BASE`

### Produção
- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `MINIO_ENDPOINT` (opcional, padrão: http://localhost:9000)
- `PORT` (opcional, padrão: 4000)

## Verificação da Release

### Saúde da aplicação
```bash
_build/prod/rel/app/bin/app eval ":observer.start"
```

### Logs da aplicação
```bash
_build/prod/rel/app/bin/app eval "Logger.info('App funcionando!')"
```

### Status da aplicação
```bash
_build/prod/rel/app/bin/app eval ":application.get_all_env(:app)"
```

## Resolução de Problemas

### Erro de banco de dados
- Verifique se `DATABASE_URL` está configurado
- Confirme se as migrações foram executadas

### Erro de MinIO
- Execute `./scripts/setup_minio.sh`
- Verifique se MinIO está rodando na porta 9000

### Erro de assets
- Execute `MIX_ENV=prod mix assets.deploy`
- Verifique se Node.js está instalado

### Problemas de compilação
- Limpe build anterior: `mix clean`
- Recompile: `mix compile`

## Comandos de Diagnóstico

```bash
# Verificar versão do Elixir/Erlang
elixir --version

# Verificar dependências
mix deps

# Verificar configuração
mix run -e "IO.inspect Application.get_all_env(:app)"

# Testar conectividade com banco
mix run -e "App.Repo.query('SELECT 1', [])"
```

## Release para Deploy

A pasta `_build/prod/rel/app/` contém a release completa que pode ser:

1. Copiada para o servidor de produção
2. Empacotada em um tar.gz:
   ```bash
   tar -czf app-release.tar.gz -C _build/prod/rel app
   ```
3. Descomprimida no servidor:
   ```bash
   tar -xzf app-release.tar.gz
   ```

## Monitoramento em Produção

- Use `:observer.start()` para monitorar recursos
- Configure loggers apropriados
- Monitore performance com métricas do Phoenix
- Configure backups do banco de dados regularmente
