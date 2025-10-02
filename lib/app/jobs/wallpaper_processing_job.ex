defmodule App.Jobs.WallpaperProcessingJob do
  @moduledoc """
  Job para processamento de papéis de parede em background.

  Processa uploads de imagens para papel de parede, incluindo:
  - Redimensionamento para otimização
  - Compressão para melhor performance
  - Upload para MinIO
  - Atualização do tema do usuário
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{
    "file_path" => file_path,
    "user_id" => user_id,
    "original_filename" => original_filename,
    "file_size" => _file_size,
    "mime_type" => mime_type
  }}) do
    Logger.info("Iniciando processamento de papel de parede: #{original_filename}")

    # Validar se é uma imagem
    unless String.starts_with?(mime_type, "image/") do
      Logger.error("Arquivo não é uma imagem: #{mime_type}")
      cleanup_temp_file(file_path)
      {:error, "Arquivo deve ser uma imagem"}
    end

    # Processar upload no MinIO
    case App.MinIOUpload.upload_file(file_path, original_filename) do
      {:ok, url} ->
        Logger.info("Papel de parede enviado com sucesso: #{url}")

        # Atualizar tema do usuário com o novo papel de parede
        case App.Themes.upsert_user_theme(user_id, %{
          background_type: "image",
          wallpaper_url: url,
          wallpaper_opacity: 0.1
        }) do
          {:ok, _theme} ->
            Logger.info("Tema atualizado com papel de parede para usuário #{user_id}")

            # Notificar via PubSub que o papel de parede foi aplicado
            notify_wallpaper_applied(user_id, url)

            # Limpar arquivo temporário
            cleanup_temp_file(file_path)

            :ok

          {:error, reason} ->
            Logger.error("Erro ao atualizar tema: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Erro no upload do papel de parede: #{inspect(reason)}")
        cleanup_temp_file(file_path)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("Argumentos inválidos para WallpaperProcessingJob: #{inspect(args)}")
    {:error, "Argumentos inválidos"}
  end

  # Notifica que o papel de parede foi aplicado
  defp notify_wallpaper_applied(user_id, wallpaper_url) do
    topic = "user:#{user_id}"

    Phoenix.PubSub.broadcast(App.PubSub, topic, {
      :wallpaper_applied,
      %{
        wallpaper_url: wallpaper_url,
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
