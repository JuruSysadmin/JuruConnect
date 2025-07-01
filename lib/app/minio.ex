defmodule App.Minio do
  @moduledoc """
  Cliente para upload de arquivos no MinIO/S3.
  Gerencia uploads de imagens e áudios do chat.
  """

  require Logger

  @bucket "chat-uploads"
  @allowed_image_types ~w(.jpg .jpeg .png .gif .webp)
  @allowed_audio_types ~w(.webm .mp3 .wav .m4a .ogg)
  @max_image_size 5_000_000
  @max_audio_size 10_000_000

  @doc """
  Faz upload de um arquivo para o MinIO/S3.

  ## Parâmetros
  - file_path: Caminho local do arquivo
  - filename: Nome do arquivo no storage
  - opts: Opções adicionais (content_type, acl, etc.)

  ## Retorna
  {:ok, url} | {:error, reason}
  """
  def upload_file(file_path, filename, opts \\ []) do
    Logger.debug("Iniciando upload: #{filename}")

    with {:ok, file_binary} <- read_file_safe(file_path),
         {:ok, _} <- validate_file_type(filename),
         {:ok, _} <- validate_file_size(file_binary, filename),
         {:ok, _result} <- perform_upload(filename, file_binary, opts) do

      url = build_public_url(filename)
      Logger.info("Upload concluído: #{filename} -> #{url}")
      {:ok, url}
    else
      error ->
        Logger.error("Falha no upload #{filename}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Retorna a URL pública de um arquivo.
  """
  def public_url(filename) do
    build_public_url(filename)
  end

  @doc """
  Verifica se um tipo de arquivo é suportado.
  """
  def supported_file_type?(filename) do
    extension = filename |> Path.extname() |> String.downcase()
    extension in (@allowed_image_types ++ @allowed_audio_types)
  end

  @doc """
  Testa a conexão com o MinIO.
  """
  def test_connection do
    Logger.info("Testando conexão com MinIO...")

    case ExAws.S3.list_buckets() |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Conexão MinIO: OK")
        {:ok, :connected}

      {:error, reason} ->
        Logger.error("Conexão MinIO falhou: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Cria o bucket se não existir.
  """
  def ensure_bucket_exists do
    Logger.info("Verificando bucket: #{@bucket}")

    case ExAws.S3.head_bucket(@bucket) |> ExAws.request() do
      {:ok, _} ->
        Logger.debug("Bucket #{@bucket} já existe")
        {:ok, :exists}

      {:error, {:http_error, 404, _}} ->
        Logger.info("Criando bucket: #{@bucket}")
        create_bucket()

      {:error, reason} ->
        Logger.error("Erro ao verificar bucket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Funções privadas

  defp read_file_safe(file_path) do
    case File.read(file_path) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} ->
        Logger.error("Erro ao ler arquivo #{file_path}: #{reason}")
        {:error, {:file_read_error, reason}}
    end
  end

  defp validate_file_type(filename) do
    if supported_file_type?(filename) do
      {:ok, :valid}
    else
      extension = Path.extname(filename)
      Logger.warning("Tipo de arquivo não suportado: #{extension}")
      {:error, {:unsupported_file_type, extension}}
    end
  end

  defp validate_file_size(file_binary, filename) do
    size = byte_size(file_binary)
    max_size = get_max_size_for_file(filename)

    if size <= max_size do
      {:ok, :valid}
    else
      Logger.warning("Arquivo muito grande: #{filename} (#{size} bytes)")
      {:error, {:file_too_large, size, max_size}}
    end
  end

  defp get_max_size_for_file(filename) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension in @allowed_image_types do
      @max_image_size
    else
      @max_audio_size
    end
  end

  defp perform_upload(filename, file_binary, opts) do
    content_type = get_content_type(filename)
    acl = Keyword.get(opts, :acl, :public_read)

    ExAws.S3.put_object(@bucket, filename, file_binary,
      content_type: content_type,
      acl: acl
    )
    |> ExAws.request()
  end

  defp get_content_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".webm" -> "audio/webm"
      ".mp3" -> "audio/mp3"
      ".wav" -> "audio/wav"
      ".m4a" -> "audio/mp4"
      ".ogg" -> "audio/ogg"
      _ -> "application/octet-stream"
    end
  end

  defp build_public_url(filename) do
    config = Application.get_env(:ex_aws, :s3, [])
    scheme = Keyword.get(config, :scheme, "http://")
    host = Keyword.get(config, :host, "localhost")
    port = Keyword.get(config, :port, 9000)

    "#{scheme}#{host}:#{port}/#{@bucket}/#{filename}"
  end

    defp create_bucket do
    case ExAws.S3.put_bucket(@bucket, "us-east-1") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Bucket #{@bucket} criado com sucesso")
        configure_bucket_policy()
        {:ok, :created}

      {:error, reason} ->
        Logger.error("Erro ao criar bucket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp configure_bucket_policy do
    case App.MinioBucketPolicy.set_public_read_policy() do
      {:ok, :configured} ->
        Logger.info("Política pública configurada automaticamente")

      {:error, reason} ->
        Logger.warning("Falha ao configurar política automática: #{inspect(reason)}")
    end
  end
end
