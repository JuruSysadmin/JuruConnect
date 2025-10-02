defmodule App.Jobs.EmailJob do
  @moduledoc """
  Job para envio de emails em background.
  
  Exemplo de uso:
  
      # Enviar email imediatamente
      %{to: "user@example.com", subject: "Bem-vindo!", body: "Olá!"}
      |> App.Jobs.EmailJob.new()
      |> Oban.insert()
      
      # Enviar email com atraso
      %{to: "user@example.com", subject: "Lembrete", body: "Não esqueça!"}
      |> App.Jobs.EmailJob.new(schedule_in: 300) # 5 minutos
      |> Oban.insert()
      
      # Enviar email em horário específico
      %{to: "user@example.com", subject: "Relatório", body: "Seu relatório está pronto!"}
      |> App.Jobs.EmailJob.new(scheduled_at: ~U[2024-01-01 09:00:00Z])
      |> Oban.insert()
  """

  use Oban.Worker, queue: :mailers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"to" => to, "subject" => subject, "body" => body}}) do
    # Aqui você implementaria o envio real do email
    # Por exemplo, usando Swoosh ou outro provedor
    
    IO.puts("Enviando email para: #{to}")
    IO.puts("Assunto: #{subject}")
    IO.puts("Conteudo: #{body}")
    
    # Simular processamento
    Process.sleep(1000)
    
    # Retornar sucesso
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    IO.puts("Argumentos invalidos para EmailJob: #{inspect(args)}")
    {:error, "Argumentos inválidos"}
  end
end
