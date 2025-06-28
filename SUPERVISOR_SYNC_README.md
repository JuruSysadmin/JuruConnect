# Sistema de Sincronização de Dados de Supervisores

Este sistema permite coletar dados de supervisores de uma API externa e armazená-los no PostgreSQL, com opção de sincronização periódica usando Oban.

## 📋 Pré-requisitos

### Dependências necessárias no `mix.exs`:

```elixir
defp deps do
  [
    # Para jobs em background (opcional, mas recomendado)
    {:oban, "~> 2.15"},
    
    # Para requisições HTTP
    {:httpoison, "~> 1.8"},
    
    # Para parsing JSON (se não tiver)
    {:jason, "~> 1.4"},
    
    # Suas outras dependências...
  ]
end
```

## 🗄️ Setup do Banco de Dados

### 1. Execute a migration:

```bash
mix ecto.migrate
```

### 2. Estrutura da tabela criada:

A tabela `supervisor_data` armazena:
- Dados agregados (objetivo, vendas, percentuais)
- Array JSON com dados individuais de cada vendedor
- Timestamp de quando os dados foram coletados
- Índices otimizados para consultas

## 🚀 Como Usar

### Opção 1: Uso Manual (Simples)

```elixir
# No IEx ou em qualquer lugar do código
alias JuruConnect.Api.SupervisorClient

# Buscar e salvar dados uma vez
{:ok, data} = SupervisorClient.fetch_and_save("https://sua-api.com/supervisores")

# Ou apenas buscar sem salvar
{:ok, raw_data} = SupervisorClient.fetch_data("https://sua-api.com/supervisores")
```

### Opção 2: Sincronização Periódica Simples

```elixir
# Inicia coleta a cada 2 horas (7200 segundos)
SupervisorClient.start_periodic_sync("https://sua-api.com/supervisores", 7200)

# Para parar
SupervisorClient.stop_periodic_sync()
```

### Opção 3: Com Oban (Recomendado para Produção)

#### 1. Configure o Oban no `config/config.exs`:

```elixir
config :juru_connect, Oban,
  repo: JuruConnect.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Coleta dados a cada 2 horas
       {"0 */2 * * *", JuruConnect.Workers.SupervisorDataWorker, 
        %{"api_url" => "https://sua-api.com/supervisores"}},
       
       # Ou a cada 30 minutos
       # {"*/30 * * * *", JuruConnect.Workers.SupervisorDataWorker, 
       #  %{"api_url" => "https://sua-api.com/supervisores"}},
     ]}
  ],
  queues: [
    default: 10,
    api_sync: 5  # Queue específica para sync de API
  ]
```

#### 2. Adicione o Oban ao `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    JuruConnect.Repo,
    {Oban, Application.fetch_env!(:juru_connect, Oban)},  # Adicione esta linha
    JuruConnectWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: JuruConnect.Supervisor]
  Supervisor.start_link(children, opts)
end
```

#### 3. Agendamento manual de jobs:

```elixir
alias JuruConnect.Workers.SupervisorDataWorker

# Executar imediatamente
%{"api_url" => "https://sua-api.com/supervisores"}
|> SupervisorDataWorker.new()
|> Oban.insert()

# Agendar para daqui 1 hora
%{"api_url" => "https://sua-api.com/supervisores"}
|> SupervisorDataWorker.new(in: 3600)
|> Oban.insert()

# Agendar para um horário específico
scheduled_time = DateTime.add(DateTime.utc_now(), 24 * 60 * 60) # amanhã
%{"api_url" => "https://sua-api.com/supervisores"}
|> SupervisorDataWorker.new(scheduled_at: scheduled_time)
|> Oban.insert()
```

## 📊 Consultando os Dados

### Exemplos de uso do context `Sales`:

```elixir
alias JuruConnect.Sales

# Buscar dados mais recentes
latest = Sales.get_latest_supervisor_data()

# Listar últimos 20 registros
recent_data = Sales.list_supervisor_data(limit: 20)

# Filtrar por período
date_from = DateTime.utc_now() |> DateTime.add(-7 * 24 * 60 * 60) # 7 dias atrás
date_to = DateTime.utc_now()

period_data = Sales.list_supervisor_data(
  date_from: date_from,
  date_to: date_to,
  limit: 50
)

# Top 10 vendedores por performance
top_performers = Sales.get_top_performers(10, date_from, date_to)

# Histórico de um vendedor específico
seller_history = Sales.get_seller_history(1217, date_from, date_to)
```

### Consultando diretamente com Ecto:

```elixir
import Ecto.Query
alias JuruConnect.{Repo, Schemas.SupervisorData}

# Dados dos últimos 7 dias
data = from(sd in SupervisorData,
  where: sd.collected_at >= ago(7, "day"),
  order_by: [desc: sd.collected_at]
) |> Repo.all()

# Buscar vendedores específicos usando JSONB
vendedores_br = from(sd in SupervisorData,
  where: fragment("? @> ?", sd.sale_supervisor, 
    ^[%{"store" => "JURUNENSE BR"}])
) |> Repo.all()

# Performance média por período
avg_performance = from(sd in SupervisorData,
  where: sd.collected_at >= ago(30, "day"),
  select: avg(sd.percentual_sale)
) |> Repo.one()
```

## 🔧 Configurações Avançadas

### Headers personalizados para a API:

```elixir
# Com autenticação
headers = [
  {"Authorization", "Bearer #{token}"},
  {"Content-Type", "application/json"}
]

SupervisorClient.fetch_and_save("https://api.com/data", headers: headers)
```

### Timeout personalizado:

```elixir
# Timeout de 60 segundos
SupervisorClient.fetch_and_save(
  "https://api.com/data", 
  timeout: 60_000
)
```

### Worker com configurações customizadas:

```elixir
%{
  "api_url" => "https://sua-api.com/supervisores",
  "headers" => [{"Authorization", "Bearer token123"}],
  "timeout" => 45000
}
|> SupervisorDataWorker.new()
|> Oban.insert()
```

## 📈 Monitoramento

### Logs automáticos:

O sistema gera logs estruturados para monitoramento:

```elixir
# Exemplo de logs gerados:
[info] Iniciando coleta de dados de supervisores api_url="https://api.com/data"
[info] Dados salvos com sucesso id=123 collected_at=2024-01-01T10:00:00Z sellers_count=45
[error] Erro na coleta de dados reason={:http_error, 500, "Internal Server Error"}
```

### Verificação de status:

```elixir
# Verificar se há dados recentes (últimas 3 horas)
recent_threshold = DateTime.add(DateTime.utc_now(), -3 * 60 * 60)
case Sales.get_latest_supervisor_data() do
  %{collected_at: collected_at} when collected_at > recent_threshold ->
    IO.puts("✅ Dados atualizados")
  _ ->
    IO.puts("⚠️  Dados desatualizados")
end
```

## 🛠️ Troubleshooting

### Problemas comuns:

1. **Erro de conexão com API**: Verifique URL e conectividade de rede
2. **Timeout**: Aumente o valor do timeout se a API for lenta
3. **Dados não salvando**: Verifique se o JSON da API está no formato esperado
4. **Worker não executando**: Confirme se o Oban está configurado corretamente

### Debug:

```elixir
# Testar apenas a requisição HTTP
{:ok, raw_data} = SupervisorClient.fetch_data("https://sua-api.com")
IO.inspect(raw_data, label: "Dados da API")

# Testar normalização dos dados
normalized = JuruConnect.Sales.normalize_api_data(raw_data)
IO.inspect(normalized, label: "Dados normalizados")
```

## 📋 Exemplo Completo

```elixir
# 1. Adicionar dependências ao mix.exs
# 2. Executar: mix deps.get && mix ecto.migrate
# 3. Configurar Oban (opcional)
# 4. Usar:

# Teste rápido
{:ok, data} = JuruConnect.Api.SupervisorClient.fetch_and_save(
  "https://sua-api.com/supervisores"
)

# Ver dados salvos
latest = JuruConnect.Sales.get_latest_supervisor_data()
IO.inspect(latest.sale_supervisor, label: "Vendedores")

# Configurar sync automático
JuruConnect.Api.SupervisorClient.start_periodic_sync(
  "https://sua-api.com/supervisores", 
  7200  # 2 horas
)
```

Com isso, você terá um sistema completo de sincronização de dados que:
- ✅ Funciona com ou sem Oban
- ✅ Suporta requisições HTTP robustas
- ✅ Armazena dados eficientemente no PostgreSQL
- ✅ Oferece consultas otimizadas
- ✅ Gera logs para monitoramento
- ✅ É facilmente configurável e extensível 