defmodule App.Jobs.ScheduledJob do
  @moduledoc """
  Job para tarefas agendadas (cron jobs).
  
  Este job é executado automaticamente baseado na configuração do cron.
  """

  use Oban.Worker, queue: :scheduled

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => task}}) do
    case task do
      "cleanup_old_messages" ->
        cleanup_old_messages()
      
      "generate_reports" ->
        generate_reports()
      
      "backup_database" ->
        backup_database()
      
      _ ->
        IO.puts("Tarefa desconhecida: #{task}")
        {:error, "Tarefa desconhecida"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    IO.puts("Argumentos invalidos para ScheduledJob: #{inspect(args)}")
    {:error, "Argumentos inválidos"}
  end

  defp cleanup_old_messages do
    IO.puts("Limpando mensagens antigas...")
    
    # Aqui você implementaria a limpeza real
    # Por exemplo, deletar mensagens mais antigas que 30 dias
    # App.Repo.delete_all(from m in App.Message, where: m.inserted_at < ago(30, "day"))
    
    Process.sleep(1000)
    :ok
  end

  defp generate_reports do
    IO.puts("Gerando relatorios...")
    
    # Aqui você implementaria a geração real de relatórios
    # Por exemplo, estatísticas de uso, relatórios financeiros, etc.
    
    Process.sleep(2000)
    :ok
  end

  defp backup_database do
    IO.puts("Fazendo backup do banco de dados...")
    
    # Aqui você implementaria o backup real
    # Por exemplo, exportar dados para arquivo, enviar para cloud storage, etc.
    
    Process.sleep(3000)
    :ok
  end
end
