# Usando com sua API Real

## URL da API: `http://10.1.1.108:8065/api/v1/dashboard/sale/12`

### 1. **Teste Rápido no Terminal**

```bash
# Inicie o IEx
iex -S mix

# Teste básico - buscar dados
api_url = "http://10.1.1.108:8065/api/v1/dashboard/sale/12"
{:ok, data} = JuruConnect.Api.SupervisorClient.fetch_data(api_url)

# Ver estrutura dos dados
IO.inspect(data, limit: :infinity, pretty: true)

# Salvar no banco
{:ok, saved_data} = JuruConnect.Sales.create_supervisor_data_from_api(data)

# Ver dados salvos
IO.puts("ID: #{saved_data.id}")
IO.puts("Performance: #{saved_data.percentual_sale}%")
IO.puts("Vendedores: #{length(saved_data.sale_supervisor)}")
```

### 2. **Configurar Coleta Automática**

```elixir
# Sync a cada 1 hora (3600 segundos)
JuruConnect.Api.SupervisorClient.start_periodic_sync(
  "http://10.1.1.108:8065/api/v1/dashboard/sale/12", 
  3600
)

# Verificar se está rodando
Process.whereis(JuruConnect.Api.SupervisorClient)

# Para parar
JuruConnect.Api.SupervisorClient.stop_periodic_sync()
```

### 3. **Consultas Úteis**

```elixir
# Dados mais recentes
latest = JuruConnect.Sales.get_latest_supervisor_data()
IO.puts("Performance atual: #{latest.percentual_sale}%")

# Últimos 5 registros
recent = JuruConnect.Sales.list_supervisor_data(limit: 5)
Enum.each(recent, fn data ->
  IO.puts("#{data.collected_at} - #{data.percentual_sale}%")
end)

# Top 5 vendedores da última coleta
if latest do
  top_sellers = latest.sale_supervisor
  |> Enum.sort_by(& &1["percentualObjective"], :desc)
  |> Enum.take(5)
  
  Enum.each(top_sellers, fn seller ->
    IO.puts("#{seller["sellerName"]}: #{seller["percentualObjective"]}%")
  end)
end
```

### 4. **Script para Executar Manualmente**

```elixir
# cole_dados.exs
api_url = "http://10.1.1.108:8065/api/v1/dashboard/sale/12"

case JuruConnect.Api.SupervisorClient.fetch_and_save(api_url) do
  {:ok, data} ->
    IO.puts("Dados coletados e salvos!")
    IO.puts("Performance: #{data.percentual_sale}%")
    IO.puts("Vendedores: #{length(data.sale_supervisor)}")
  {:error, reason} ->
    IO.puts("Erro: #{inspect(reason)}")
end
```

### 5. **Monitoramento**

```elixir
# Verificar se dados estão atualizados (últimas 2 horas)
threshold = DateTime.add(DateTime.utc_now(), -2 * 60 * 60)
latest = JuruConnect.Sales.get_latest_supervisor_data()

case latest do
  %{collected_at: collected_at} when collected_at > threshold ->
    IO.puts("Dados atualizados")
  _ ->
    IO.puts("Dados desatualizados - executar coleta manual")
end
```

### 6. **Troubleshooting**

Se der erro de conexão:

```bash
# Teste direto no terminal
curl http://10.1.1.108:8065/api/v1/dashboard/sale/12

# Ou no navegador
# Acesse: http://10.1.1.108:8065/api/v1/dashboard/sale/12
```

Se der erro de parsing:

```elixir
# Debug - ver dados brutos
{:ok, raw_data} = JuruConnect.Api.SupervisorClient.fetch_data(api_url)
IO.inspect(raw_data, label: "Dados da API")

# Ver se o formato está diferente do esperado
```

### 7. **Configuração Oban (Opcional)**

Para jobs mais robustos, adicione ao `config/config.exs`:

```elixir
config :app, Oban,
  repo: App.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # A cada hora
       {"0 * * * *", JuruConnect.Workers.SupervisorDataWorker, 
        %{"api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12"}},
       
       # A cada 30 minutos
       # {"*/30 * * * *", JuruConnect.Workers.SupervisorDataWorker, 
       #  %{"api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12"}},
     ]}
  ],
  queues: [default: 10, api_sync: 5]
```

### 8. **Próximos Passos**

1. **Teste a conectividade** primeiro
2. **Configure sync automático** se estiver funcionando  
3. **Crie dashboards** usando os dados históricos
4. **Configure alertas** para metas não atingidas
5. **Monitore logs** para acompanhar coletas

### 9. **Comandos Úteis**

```bash
# Executar coleta manual
mix run -e "JuruConnect.Api.SupervisorClient.fetch_and_save('http://10.1.1.108:8065/api/v1/dashboard/sale/12')"

# Ver últimos dados
mix run -e "IO.inspect(JuruConnect.Sales.get_latest_supervisor_data())"

# Contar registros
mix run -e "IO.puts('Total: #{length(JuruConnect.Sales.list_supervisor_data(limit: 1000))}')"
``` 