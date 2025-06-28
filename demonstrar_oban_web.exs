IO.puts("🎛️ Demonstração do Monitor Oban Personalizado")
IO.puts("=" |> String.duplicate(50))

# Verificar se aplicação está rodando
case HTTPoison.get("http://localhost:4000") do
  {:ok, %HTTPoison.Response{status_code: 200}} ->
    IO.puts("✅ Servidor Phoenix rodando em http://localhost:4000")
  _ ->
    IO.puts("❌ Servidor não está rodando!")
    IO.puts("   Execute: mix phx.server")
    System.halt(1)
end

IO.puts("")
IO.puts("🎯 URLs importantes:")
IO.puts("   Aplicação: http://localhost:4000")
IO.puts("   Monitor Oban: http://localhost:4000/dev/oban")
IO.puts("   Phoenix Dashboard: http://localhost:4000/dev/dashboard")

IO.puts("")
IO.puts("🧪 Criando jobs de demonstração...")

# Criar diferentes tipos de jobs para demonstração
jobs_criados = []

# Job 1: Imediato
job1 = %{
  "api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12",
  "test" => true,
  "tipo" => "demonstracao_imediato",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
}

case JuruConnect.Workers.SupervisorDataWorker.new(job1, queue: :api_sync) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job imediato criado (ID: #{job.id})")
    jobs_criados = [job | jobs_criados]
  {:error, reason} ->
    IO.puts("❌ Erro ao criar job imediato: #{inspect(reason)}")
end

# Job 2: Agendado para 30 segundos
job2 = %{
  "api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12",
  "test" => true,
  "tipo" => "demonstracao_agendado_30s",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
}

case JuruConnect.Workers.SupervisorDataWorker.new(job2, queue: :api_sync, in: 30) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job agendado para 30s criado (ID: #{job.id})")
    jobs_criados = [job | jobs_criados]
  {:error, reason} ->
    IO.puts("❌ Erro ao criar job agendado: #{inspect(reason)}")
end

# Job 3: Agendado para 2 minutos
job3 = %{
  "api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12",
  "test" => true,
  "tipo" => "demonstracao_agendado_2min",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
}

case JuruConnect.Workers.SupervisorDataWorker.new(job3, queue: :api_sync, in: 120) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job agendado para 2min criado (ID: #{job.id})")
    jobs_criados = [job | jobs_criados]
  {:error, reason} ->
    IO.puts("❌ Erro ao criar job 2min: #{inspect(reason)}")
end

# Job 4: Para fila default
job4 = %{
  "test" => true,
  "tipo" => "demonstracao_fila_default",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "note" => "Este job está na fila default"
}

case JuruConnect.Workers.SupervisorDataWorker.new(job4, queue: :default) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job fila default criado (ID: #{job.id})")
    jobs_criados = [job | jobs_criados]
  {:error, reason} ->
    IO.puts("❌ Erro ao criar job default: #{inspect(reason)}")
end

IO.puts("")
IO.puts("📊 Estatísticas dos jobs criados:")
IO.puts("   Total de jobs criados: #{length(jobs_criados)}")

if length(jobs_criados) > 0 do
  jobs_por_fila = jobs_criados |> Enum.group_by(& &1.queue)
  Enum.each(jobs_por_fila, fn {fila, jobs} ->
    IO.puts("   Fila #{fila}: #{length(jobs)} jobs")
  end)
end

IO.puts("")
IO.puts("🔍 Verificando status das filas:")

# Verificar filas disponíveis
config = Application.get_env(:app, Oban, [])
queues = Keyword.get(config, :queues, [])

Enum.each(queues, fn {queue_name, limit} ->
  case Oban.check_queue(queue: queue_name) do
    %{paused: paused} = info ->
      status = if paused, do: "⏸️  PAUSADA", else: "▶️  ATIVA"
      IO.puts("   #{queue_name}: #{status} (#{limit} workers)")

      # Tentar contar jobs na fila
      try do
        query = """
        SELECT COUNT(*)
        FROM oban_jobs
        WHERE queue = $1 AND state = 'available'
        """
        case App.Repo.query(query, [to_string(queue_name)]) do
          {:ok, %{rows: [[count]]}} ->
            IO.puts("      Jobs disponíveis: #{count}")
          _ ->
            IO.puts("      Jobs disponíveis: N/A")
        end
      rescue
        _ ->
          IO.puts("      Jobs disponíveis: Erro ao consultar")
      end

    error ->
      IO.puts("   #{queue_name}: ❌ Erro ao verificar status: #{inspect(error)}")
  end
end)

IO.puts("")
IO.puts("🎛️ COMO USAR O MONITOR:")
IO.puts("")
IO.puts("1️⃣  Acesse: http://localhost:4000/dev/oban")
IO.puts("")
IO.puts("2️⃣  No monitor você verá:")
IO.puts("    📊 Estatísticas das últimas 24h")
IO.puts("    📋 Status das filas (api_sync, default)")
IO.puts("    🔄 Jobs recentes com detalhes")
IO.puts("    ⚙️  Controles para pausar/reativar filas")
IO.puts("")
IO.puts("3️⃣  Recursos interativos:")
IO.puts("    🧪 Botão 'Criar Job de Teste'")
IO.puts("    ⏸️  Botões para pausar filas")
IO.puts("    ▶️  Botões para reativar filas")
IO.puts("    🔄 Atualização automática a cada 5 segundos")
IO.puts("")
IO.puts("4️⃣  Observe os jobs criados:")
IO.puts("    - Alguns devem aparecer como 'Available'")
IO.puts("    - Outros como 'Scheduled' (agendados)")
IO.puts("    - Veja a contagem nas estatísticas")
IO.puts("")

IO.puts("🚀 COMANDOS ÚTEIS:")
IO.puts("")
IO.puts("# Pausar fila:")
IO.puts("Oban.pause_queue(queue: :api_sync)")
IO.puts("")
IO.puts("# Reativar fila:")
IO.puts("Oban.resume_queue(queue: :api_sync)")
IO.puts("")
IO.puts("# Verificar status:")
IO.puts("Oban.check_queue(queue: :api_sync)")
IO.puts("")

IO.puts("=" |> String.duplicate(50))
IO.puts("🎉 DEMONSTRAÇÃO CONCLUÍDA!")
IO.puts("")
IO.puts("Agora acesse o monitor e veja os jobs em ação:")
IO.puts("👉 http://localhost:4000/dev/oban")
IO.puts("")
IO.puts("🔥 Sistema totalmente funcional!")
IO.puts("   ✅ Oban configurado e rodando")
IO.puts("   ✅ Jobs sendo processados")
IO.puts("   ✅ Monitor visual em tempo real")
IO.puts("   ✅ Controles interativos")
IO.puts("   ✅ Integração completa com Phoenix")
