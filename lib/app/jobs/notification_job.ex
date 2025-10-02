defmodule App.Jobs.NotificationJob do
  @moduledoc """
  Job para processar notificações em background.
  
  Exemplo de uso:
  
      # Notificação imediata
      %{user_id: 123, message: "Nova mensagem recebida", type: "message"}
      |> App.Jobs.NotificationJob.new()
      |> Oban.insert()
      
      # Notificação com prioridade
      %{user_id: 123, message: "Sistema em manutenção", type: "system"}
      |> App.Jobs.NotificationJob.new(priority: 1)
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "message" => message, "type" => type}}) do
    # Aqui você implementaria o processamento real da notificação
    # Por exemplo, salvar no banco, enviar push notification, etc.
    
    IO.puts("Processando notificacao para usuario #{user_id}")
    IO.puts("Mensagem: #{message}")
    IO.puts("Tipo: #{type}")
    
    # Simular processamento
    Process.sleep(500)
    
    # Aqui você poderia salvar a notificação no banco
    # App.Repo.insert(%App.Notification{user_id: user_id, message: message, type: type})
    
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    IO.puts("Argumentos invalidos para NotificationJob: #{inspect(args)}")
    {:error, "Argumentos inválidos"}
  end
end
