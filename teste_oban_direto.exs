IO.puts("🧪 Testando Oban Web Dashboard...")
IO.puts("Servidor deve estar rodando em: http://localhost:4000")
IO.puts("Dashboard deve estar acessível em: http://localhost:4000/dev/oban")

# Verificar se Oban está rodando
case Process.whereis(Oban) do
  nil ->
    IO.puts("❌ Oban não está rodando!")

  pid ->
    IO.puts("✅ Oban está rodando (PID: #{inspect(pid)})")

    # Verificar filas configuradas
    IO.puts("\n📋 Filas configuradas:")
    config = Application.get_env(:app, Oban)
    Enum.each(config[:queues], fn {queue, workers} ->
      IO.puts("  - #{queue}: #{workers} workers")
    end)

    # Criar job de teste simples
    IO.puts("\n🚀 Criando job de teste...")

    job_args = %{
      "api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12",
      "timeout" => 30000,
      "test" => true
    }

    case JuruConnect.Workers.SupervisorDataWorker.new(job_args, queue: :api_sync) |> Oban.insert() do
      {:ok, job} ->
        IO.puts("✅ Job criado com sucesso!")
        IO.puts("   ID: #{job.id}")
        IO.puts("   Queue: #{job.queue}")
        IO.puts("   Estado: #{job.state}")
        IO.puts("   Args: #{inspect(job.args)}")

      {:error, reason} ->
        IO.puts("❌ Erro ao criar job: #{inspect(reason)}")
    end

    # Verificar jobs nas filas
    IO.puts("\n📊 Status das filas:")
    available_jobs = Oban.peek_queue(:api_sync, 5)
    IO.puts("  api_sync: #{length(available_jobs)} jobs disponíveis")

    default_jobs = Oban.peek_queue(:default, 5)
    IO.puts("  default: #{length(default_jobs)} jobs disponíveis")

    IO.puts("\n🎯 Próximos passos:")
    IO.puts("1. Acesse: http://localhost:4000/dev/oban")
    IO.puts("2. Vá para a seção 'Jobs'")
    IO.puts("3. Procure por jobs na fila 'api_sync'")
    IO.puts("4. Explore as outras seções do dashboard")
end
