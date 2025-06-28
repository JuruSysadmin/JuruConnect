defmodule MonitorOban do
  @moduledoc """
  Script para monitorar status do Oban via linha de comando.

  Exibe informações sobre:
  - Jobs por estado (pendentes, executando, falhados)
  - Performance das últimas horas
  - Estado das filas
  - Alertas de problemas

  Execute com: mix run monitor_oban.exs
  """

  import Ecto.Query
  alias App.Repo

  def run do
    IO.puts("=== MONITOR OBAN ===")
    IO.puts("Coletado em: #{DateTime.utc_now()}")

    if oban_configured?() do
      display_queue_status()
      display_job_statistics()
      display_recent_activity()
      display_health_check()
    else
      display_setup_instructions()
    end
  end

  defp oban_configured? do
    case Code.ensure_loaded?(Oban.Job) do
      true ->
        try do
          Repo.query!("SELECT COUNT(*) FROM oban_jobs LIMIT 1")
          true
        rescue
          _ -> false
        end
      false -> false
    end
  end

  defp display_queue_status do
    IO.puts("\n--- STATUS DAS FILAS ---")

    stats = get_queue_stats()

    IO.puts("Available (aguardando):  #{stats.available}")
    IO.puts("Executing (executando):  #{stats.executing}")
    IO.puts("Completed (concluídos):  #{stats.completed}")
    IO.puts("Retryable (para retry):  #{stats.retryable}")
    IO.puts("Cancelled (cancelados):  #{stats.cancelled}")
    IO.puts("Discarded (descartados): #{stats.discarded}")
  end

  defp display_job_statistics do
    IO.puts("\n--- ESTATÍSTICAS (ÚLTIMAS 24H) ---")

    stats = get_daily_stats()

    IO.puts("Total processados: #{stats.total_processed}")
    IO.puts("Taxa de sucesso:   #{stats.success_rate}%")
    IO.puts("Jobs por hora:     #{stats.jobs_per_hour}")

    if is_list(stats.top_workers) and length(stats.top_workers) > 0 do
      IO.puts("\nWorkers mais ativos:")
      Enum.each(stats.top_workers, fn {worker, count} ->
        IO.puts("  #{worker}: #{count} jobs")
      end)
    end
  end

  defp display_recent_activity do
    IO.puts("\n--- ATIVIDADE RECENTE ---")

    recent_jobs = get_recent_jobs()

    if length(recent_jobs) > 0 do
      Enum.each(recent_jobs, fn job ->
        status_icon = case job.state do
          "completed" -> "✅"
          "retryable" -> "🔄"
          "executing" -> "⏳"
          "available" -> "⏸️ "
          _ -> "❓"
        end

        worker_name = job.worker |> String.split(".") |> List.last()
        time_ago = format_time_ago(job.inserted_at)

        IO.puts("  #{status_icon} #{worker_name} - #{time_ago}")
      end)
    else
      IO.puts("Nenhuma atividade recente")
    end
  end

  defp display_health_check do
    IO.puts("\n--- VERIFICAÇÃO DE SAÚDE ---")

    case health_status() do
      :healthy ->
        IO.puts("✅ Oban funcionando normalmente")
      {:warning, message} ->
        IO.puts("⚠️  Atenção: #{message}")
      {:critical, message} ->
        IO.puts("🚨 Problema crítico: #{message}")
        IO.puts("   Recomendação: Investigar imediatamente")
    end
  end

  defp display_setup_instructions do
    IO.puts("\n❌ Oban não configurado ou tabelas não encontradas")
    IO.puts("\nPara configurar:")
    IO.puts("1. Adicione {:oban, \"~> 2.15\"} ao mix.exs")
    IO.puts("2. Execute: mix deps.get")
    IO.puts("3. Execute: mix ecto.gen.migration add_oban_jobs_table")
    IO.puts("4. Execute: mix ecto.migrate")
    IO.puts("5. Configure no application.ex")
    IO.puts("\nVeja configuracao_oban_dashboard.md para detalhes")
  end

  defp get_queue_stats do
    base_query = from(j in Oban.Job, select: count(j.id))

    %{
      available: execute_count_query(base_query, "available"),
      executing: execute_count_query(base_query, "executing"),
      completed: execute_count_query(base_query, "completed"),
      retryable: execute_count_query(base_query, "retryable"),
      cancelled: execute_count_query(base_query, "cancelled"),
      discarded: execute_count_query(base_query, "discarded")
    }
  end

  defp get_daily_stats do
    day_ago = DateTime.add(DateTime.utc_now(), -24 * 60 * 60)

    total_query = from(j in Oban.Job,
      where: j.inserted_at > ^day_ago,
      select: count(j.id)
    )

    success_query = from(j in Oban.Job,
      where: j.inserted_at > ^day_ago and j.state == "completed",
      select: count(j.id)
    )

    worker_query = from(j in Oban.Job,
      where: j.inserted_at > ^day_ago,
      group_by: j.worker,
      select: {j.worker, count(j.id)},
      order_by: [desc: count(j.id)],
      limit: 5
    )

    total = execute_query(total_query, 0)
    success = execute_query(success_query, 0)
    top_workers = execute_query(worker_query, [])

    success_rate = if total > 0, do: Float.round(success / total * 100, 1), else: 0
    jobs_per_hour = Float.round(total / 24, 1)

    %{
      total_processed: total,
      success_rate: success_rate,
      jobs_per_hour: jobs_per_hour,
      top_workers: top_workers
    }
  end

  defp get_recent_jobs do
    query = from(j in Oban.Job,
      order_by: [desc: j.inserted_at],
      limit: 10,
      select: %{
        worker: j.worker,
        state: j.state,
        inserted_at: j.inserted_at,
        attempted_at: j.attempted_at
      }
    )

    execute_query(query, [])
  end

  defp health_status do
    stats = get_queue_stats()

    cond do
      stats.retryable > 50 ->
        {:critical, "Muitos jobs falhando (#{stats.retryable})"}
      stats.available > 1000 ->
        {:critical, "Fila muito cheia (#{stats.available} jobs)"}
      stats.executing > 100 ->
        {:critical, "Muitos jobs executando (#{stats.executing})"}
      stats.retryable > 10 ->
        {:warning, "Alguns jobs falhando (#{stats.retryable})"}
      stats.available > 100 ->
        {:warning, "Fila crescendo (#{stats.available} jobs)"}
      stats.available == 0 and stats.executing == 0 ->
        {:warning, "Nenhuma atividade recente"}
      true ->
        :healthy
    end
  end

  defp execute_count_query(base_query, state) do
    query = base_query |> where([j], j.state == ^state)
    execute_query(query, 0)
  end

  defp execute_query(query, default) do
    try do
      Repo.one(query) || default
    rescue
      _ -> default
    end
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff < 60 -> "#{diff}s atrás"
      diff < 3600 -> "#{div(diff, 60)}m atrás"
      diff < 86400 -> "#{div(diff, 3600)}h atrás"
      true -> "#{div(diff, 86400)}d atrás"
    end
  end
end

MonitorOban.run()
