defmodule App.Jobs.MediaProcessingJob do
  @moduledoc """
  Job para processamento de mídia em background.

  Exemplo de uso:

      # Processar imagem do chat
      %{
        file_path: "/tmp/image.jpg",
        original_filename: "photo.jpg",
        file_size: 1024000,
        mime_type: "image/jpeg",
        treaty_id: "treaty_123",
        user_id: "user_456",
        message_id: "msg_789"
      }
      |> App.Jobs.MediaProcessingJob.new()
      |> Oban.insert()
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{
    "file_path" => file_path,
    "original_filename" => original_filename,
    "file_size" => file_size,
    "mime_type" => mime_type,
    "treaty_id" => treaty_id,
    "user_id" => user_id,
    "message_id" => message_id
  }}) do
    Logger.info("Iniciando processamento de mídia: #{original_filename}")

    # Processar upload no MinIO
    case App.MinIOUpload.upload_file(file_path, original_filename) do
      {:ok, url} ->
        Logger.info("Upload concluído: #{url}")

        # Criar anexo na mensagem
        attachment_data = %{
          filename: Path.basename(url),
          original_filename: original_filename,
          file_size: file_size,
          mime_type: mime_type,
          file_url: url
        }

        case App.Chat.create_image_attachment(message_id, user_id, attachment_data) do
          {:ok, _attachment} ->
            Logger.info("Anexo criado com sucesso para mensagem #{message_id}")

            # Notificar via PubSub que o upload foi concluído
            notify_upload_complete(treaty_id, message_id, url)

            # Limpar arquivo temporário
            cleanup_temp_file(file_path)

            :ok

          {:error, reason} ->
            Logger.error("Erro ao criar anexo: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Erro no upload para MinIO: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("Argumentos inválidos para MediaProcessingJob: #{inspect(args)}")
    {:error, "Argumentos inválidos"}
  end

  # Notifica que o upload foi concluído
  defp notify_upload_complete(treaty_id, message_id, file_url) do
    topic = "treaty:#{treaty_id}"

    Phoenix.PubSub.broadcast(App.PubSub, topic, {
      :upload_complete,
      %{
        message_id: message_id,
        file_url: file_url,
        timestamp: DateTime.utc_now()
      }
    })
  end

  # Remove arquivo temporário
  defp cleanup_temp_file(file_path) do
    case File.rm(file_path) do
      :ok ->
        Logger.debug("Arquivo temporário removido: #{file_path}")
      {:error, reason} ->
        Logger.warning("Erro ao remover arquivo temporário #{file_path}: #{inspect(reason)}")
    end
  end
end
