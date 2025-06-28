# Configurando Dashboard do Oban

## Visão Geral

O Oban Web Dashboard é uma interface visual para monitorar:
- **Filas e Jobs**: Estado atual, pendentes, falhados
- **Performance**: Throughput, latência, estatísticas
- **Histórico**: Jobs executados, erros, retry
- **Configuração**: Pausar/despausar filas

## Instalação e Configuração

### 1. **Adicionar Dependência**

No `mix.exs`, adicione:

```elixir
defp deps do
  [
    {:oban, "~> 2.15"},
    {:oban_web, "~> 2.10"},
    # ... outras dependências
  ]
end
```

### 2. **Instalar Dependências**

```bash
mix deps.get
```

### 3. **Configurar Rota**

No `lib/app_web/router.ex`:

```elixir
# Para desenvolvimento
if Application.compile_env(:app, :dev_routes) do
  scope "/dev" do
    pipe_through :browser
    
    # Dashboard do Oban
    forward "/oban", Oban.Web.Router
    
    # Outros dashboards...
    live_dashboard "/dashboard", metrics: AppWeb.Telemetry
  end
end

# Para produção (com autenticação)
scope "/admin" do
  pipe_through [:browser, :admin_auth]  # Seu pipeline de auth
  
  forward "/oban", Oban.Web.Router
end
```

### 4. **Configurar Oban (se ainda não estiver)**

No `config/config.exs`:

```elixir
config :app, Oban,
  repo: App.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", JuruConnect.Workers.SupervisorDataWorker, 
        %{"api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12"}}
     ]}
  ],
  queues: [
    default: 10,
    api_sync: 5
  ]
```

### 5. **Adicionar ao Application**

No `lib/app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    App.Repo,
    {Oban, Application.fetch_env!(:app, Oban)},
    AppWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: App.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Acessando o Dashboard

### **Desenvolvimento:**
```
http://localhost:4000/dev/oban
```

### **Produção:**
```
https://seudominio.com/admin/oban
```

## Funcionalidades do Dashboard

### **1. Overview**
- Jobs processados hoje
- Taxa de sucesso/falha
- Throughput por minuto
- Filas ativas

### **2. Jobs**
- **Available**: Aguardando execução
- **Executing**: Em execução
- **Completed**: Concluídos
- **Retryable**: Para retry
- **Cancelled**: Cancelados
- **Discarded**: Descartados

### **3. Queues**
- Estado de cada fila
- Pausar/despausar filas
- Número de jobs por fila
- Configuração de concorrência

### **4. Cron**
- Jobs agendados
- Próximas execuções
- Histórico de execuções

## Comandos Úteis no IEx

```elixir
# Ver status das filas
Oban.check_queue(queue: :api_sync)

# Pausar fila
Oban.pause_queue(queue: :api_sync)

# Despausar fila
Oban.resume_queue(queue: :api_sync)

# Ver jobs pendentes
from(j in Oban.Job, where: j.state == "available") |> App.Repo.all()

# Ver jobs falhados
from(j in Oban.Job, where: j.state == "retryable") |> App.Repo.all()

# Estatísticas
Oban.drain_queue(queue: :api_sync, with_safety: false)
```

## Monitoramento Personalizado

### **Script de Monitoramento**

```elixir
# monitor_oban.exs
defmodule MonitorOban do
  import Ecto.Query
  alias App.Repo
  
  def status do
    stats = queue_stats()
    
    IO.puts("=== OBAN STATUS ===")
    IO.puts("Available: #{stats.available}")
    IO.puts("Executing: #{stats.executing}")
    IO.puts("Retryable: #{stats.retryable}")
    IO.puts("Completed (last hour): #{stats.completed_last_hour}")
    
    if stats.retryable > 0 do
      IO.puts("\n⚠️  #{stats.retryable} jobs falharam e estão aguardando retry")
    end
    
    if stats.available > 100 do
      IO.puts("\n⚠️  #{stats.available} jobs na fila - possível gargalo")
    end
  end
  
  defp queue_stats do
    base_query = from(j in Oban.Job, select: count(j.id))
    hour_ago = DateTime.add(DateTime.utc_now(), -3600)
    
    %{
      available: base_query |> where([j], j.state == "available") |> Repo.one(),
      executing: base_query |> where([j], j.state == "executing") |> Repo.one(),
      retryable: base_query |> where([j], j.state == "retryable") |> Repo.one(),
      completed_last_hour: base_query 
        |> where([j], j.state == "completed" and j.completed_at > ^hour_ago) 
        |> Repo.one()
    }
  end
end

MonitorOban.status()
```

Execute com:
```bash
mix run monitor_oban.exs
```

## Alertas e Notificações

### **Script de Alerta**

```elixir
# check_oban_health.exs
defmodule ObanHealthCheck do
  def check do
    case health_status() do
      :healthy -> 
        IO.puts("✅ Oban saudável")
      {:warning, message} -> 
        IO.puts("⚠️  Aviso: #{message}")
      {:critical, message} -> 
        IO.puts("🚨 Crítico: #{message}")
        # Aqui você pode enviar email, Slack, etc.
    end
  end
  
  defp health_status do
    stats = queue_stats()
    
    cond do
      stats.retryable > 50 -> 
        {:critical, "Muitos jobs falhando: #{stats.retryable}"}
      stats.available > 1000 -> 
        {:critical, "Fila muito cheia: #{stats.available}"}
      stats.retryable > 10 -> 
        {:warning, "Jobs falhando: #{stats.retryable}"}
      stats.available > 100 -> 
        {:warning, "Fila crescendo: #{stats.available}"}
      true -> 
        :healthy
    end
  end
end
```

## Configuração para Produção

### **Autenticação Básica**

```elixir
# router.ex
pipeline :admin_auth do
  plug Plug.BasicAuth, username: "admin", password: "senha_secreta"
end

scope "/admin" do
  pipe_through [:browser, :admin_auth]
  forward "/oban", Oban.Web.Router
end
```

### **Configuração de Ambiente**

```elixir
# config/prod.exs
config :app, Oban,
  repo: App.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron, crontab: [
      {"0 * * * *", JuruConnect.Workers.SupervisorDataWorker, 
       %{"api_url" => System.get_env("API_URL")}}
    ]}
  ],
  queues: [
    default: 25,
    api_sync: 10,
    mailers: 20
  ]
```

## Troubleshooting

### **Jobs Presos**

```elixir
# Ver jobs executando há muito tempo
from(j in Oban.Job, 
  where: j.state == "executing" and j.attempted_at < ago(1, "hour")
) |> App.Repo.all()

# Cancelar job específico
Oban.cancel_job(job_id)
```

### **Performance Issues**

```elixir
# Ver jobs mais lentos
from(j in Oban.Job,
  where: not is_nil(j.completed_at),
  select: %{
    worker: j.worker,
    duration: fragment("EXTRACT(EPOCH FROM (? - ?))", j.completed_at, j.attempted_at)
  },
  order_by: [desc: fragment("EXTRACT(EPOCH FROM (? - ?))", j.completed_at, j.attempted_at)],
  limit: 10
) |> App.Repo.all()
```

Com essa configuração, você terá visibilidade completa sobre o estado dos seus jobs do Oban! 