defmodule App.Jobs do
  @moduledoc """
  Módulo helper para facilitar o uso dos jobs do Oban.
  """

  @doc """
  Envia um email em background.

  ## Exemplos

      # Email imediato
      App.Jobs.send_email("user@example.com", "Bem-vindo!", "Olá!")

      # Email com atraso (5 minutos)
      App.Jobs.send_email("user@example.com", "Lembrete", "Não esqueça!", delay: 300)

      # Email agendado
      App.Jobs.send_email("user@example.com", "Relatório", "Seu relatório!",
        scheduled_at: ~U[2024-01-01 09:00:00Z])
  """
  def send_email(to, subject, body, opts \\ []) do
    args = %{"to" => to, "subject" => subject, "body" => body}

    App.Jobs.EmailJob.new(args, opts)
    |> Oban.insert()
  end

  @doc """
  Envia uma notificação em background.

  ## Exemplos

      # Notificação imediata
      App.Jobs.send_notification(123, "Nova mensagem", "message")

      # Notificação com prioridade
      App.Jobs.send_notification(123, "Sistema em manutenção", "system", priority: 1)
  """
  def send_notification(user_id, message, type, opts \\ []) do
    args = %{"user_id" => user_id, "message" => message, "type" => type}

    App.Jobs.NotificationJob.new(args, opts)
    |> Oban.insert()
  end

  @doc """
  Processa mídia em background.

  ## Exemplos

      # Processar imagem
      App.Jobs.process_media("/uploads/image.jpg", 123, "image")

      # Processar vídeo com retry
      App.Jobs.process_media("/uploads/video.mp4", 123, "video", max_attempts: 3)
  """
  def process_media(file_path, user_id, type, opts \\ []) do
    args = %{"file_path" => file_path, "user_id" => user_id, "type" => type}

    App.Jobs.MediaProcessingJob.new(args, opts)
    |> Oban.insert()
  end

  @doc """
  Executa uma tarefa agendada.

  ## Exemplos

      # Limpar mensagens antigas
      App.Jobs.run_scheduled_task("cleanup_old_messages")

      # Gerar relatórios
      App.Jobs.run_scheduled_task("generate_reports")
  """
  def run_scheduled_task(task, opts \\ []) do
    args = %{"task" => task}

    App.Jobs.ScheduledJob.new(args, opts)
    |> Oban.insert()
  end

  @doc """
  Lista jobs em execução.
  """
  def list_jobs do
    Oban.Job
    |> App.Repo.all()
    |> Enum.map(fn job ->
      %{
        id: job.id,
        queue: job.queue,
        state: job.state,
        args: job.args,
        inserted_at: job.inserted_at,
        scheduled_at: job.scheduled_at
      }
    end)
  end

  @doc """
  Cancela um job.
  """
  def cancel_job(job_id) do
    case Oban.cancel_job(job_id) do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> {:error, reason}
    end
  end
end
