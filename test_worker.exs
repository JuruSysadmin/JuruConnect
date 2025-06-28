# Script para testar o worker do Oban
IO.puts("=== Testando Worker do Dashboard ===")

# 1. Verificar se há snapshots no banco
IO.puts("\n1. Verificando snapshots existentes...")
snapshots_count = App.Repo.aggregate(App.Dashboard.DashboardSnapshot, :count, :id)
IO.puts("Total de snapshots: #{snapshots_count}")

# 2. Testar ApiClient diretamente
IO.puts("\n2. Testando ApiClient...")
case App.ApiClient.fetch_dashboard_summary() do
  {:ok, data} ->
    IO.puts("ApiClient funcionando! Dados: #{inspect(data)}")
  {:error, reason} ->
    IO.puts("Erro no ApiClient: #{inspect(reason)}")
end

# 3. Testar fetch de companies
IO.puts("\n3. Testando fetch de companies...")
case App.ApiClient.fetch_companies_data() do
  {:ok, data} ->
    IO.puts("Companies API funcionando! Total de companies: #{length(Map.get(data, :companies, []))}")
  {:error, reason} ->
    IO.puts("Erro na Companies API: #{inspect(reason)}")
end

# 4. Executar worker manualmente
IO.puts("\n4. Executando worker manualmente...")
case App.Workers.DashboardFetchWorker.fetch_and_store_dashboard_data() do
  {:ok, snapshot} ->
    IO.puts("Worker executado com sucesso! Snapshot ID: #{snapshot.id}")
    IO.puts("   Status: #{snapshot.fetch_status}")
    IO.puts("   Fetched at: #{snapshot.fetched_at}")
  {:error, reason} ->
    IO.puts("Erro no worker: #{inspect(reason)}")
end

# 5. Verificar novamente os snapshots
IO.puts("\n5. Verificando snapshots após execução...")
new_snapshots_count = App.Repo.aggregate(App.Dashboard.DashboardSnapshot, :count, :id)
IO.puts("Total de snapshots após execução: #{new_snapshots_count}")

# 6. Enfileirar job para execução via Oban
IO.puts("\n6. Enfileirando job no Oban...")
case App.Workers.DashboardFetchWorker.enqueue_fetch_job() do
  {:ok, job} ->
    IO.puts("Job enfileirado com sucesso! Job ID: #{job.id}")
  {:error, reason} ->
    IO.puts("Erro ao enfileirar job: #{inspect(reason)}")
end

IO.puts("\n=== Teste concluído ===")
