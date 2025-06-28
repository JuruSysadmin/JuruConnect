defmodule TestarObanWeb do
  @moduledoc """
  Script para gerar jobs de teste no Oban e visualizar no dashboard.

  Execute com: mix run testar_oban_web.exs
  Depois acesse: http://localhost:4000/dev/oban
  """

  def run do
    IO.puts("Criando jobs de teste para o Oban Web Dashboard...")

    create_test_jobs()

    IO.puts("\nJobs criados! Acesse o dashboard:")
    IO.puts("http://localhost:4000/dev/oban")
    IO.puts("\nVocê verá:")
    IO.puts("- Jobs na fila 'api_sync'")
    IO.puts("- Status dos jobs (Available, Executing, Completed)")
    IO.puts("- Estatísticas de performance")
    IO.puts("- Controles para pausar/despausar filas")
  end

  defp create_test_jobs do
    api_url = "http://10.1.1.108:8065/api/v1/dashboard/sale/12"

    # Job imediato
    job1 = %{
      "api_url" => api_url,
      "timeout" => 30000
    }
    |> JuruConnect.Workers.SupervisorDataWorker.new()

    # Job agendado para 1 minuto
    job2 = %{
      "api_url" => api_url,
      "timeout" => 30000
    }
    |> JuruConnect.Workers.SupervisorDataWorker.new(in: 60)

    # Job agendado para 5 minutos
    job3 = %{
      "api_url" => api_url,
      "timeout" => 30000
    }
    |> JuruConnect.Workers.SupervisorDataWorker.new(in: 300)

    # Inserir jobs
    case Oban.insert_all([job1, job2, job3]) do
      {:ok, jobs} ->
        IO.puts("✅ #{length(jobs)} jobs criados com sucesso!")
        Enum.each(jobs, fn job ->
          status = if job.scheduled_at > DateTime.utc_now() do
            "agendado para #{job.scheduled_at}"
          else
            "na fila para execução"
          end
          IO.puts("   Job #{job.id}: #{status}")
        end)

      {:error, reason} ->
        IO.puts("❌ Erro ao criar jobs: #{inspect(reason)}")
    end
  end
end

TestarObanWeb.run()
