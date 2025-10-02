defmodule App.MinIOUpload do
  @moduledoc """
  Módulo para gerenciar uploads de arquivos no MinIO.

  Salva arquivos no bucket 'juruconnect' e retorna URLs públicas.
  """

  require Logger

  @bucket "juruconnect"
  @max_file_size 5_000_000 # 5MB
  @allowed_extensions ~w(.jpg .jpeg .png .gif .webp)
  @base_url "http://10.1.1.168:9000"

  @doc """
  Salva um arquivo no MinIO e retorna a URL pública.

  ## Parâmetros
  - `path`: Caminho temporário do arquivo
  - `original_name`: Nome original do arquivo

  ## Retorno
  - `{:ok, url}`: URL pública do arquivo
  - `{:error, reason}`: Erro no upload
  """
  def upload_file(path, original_name) when is_binary(path) and is_binary(original_name) do
    with :ok <- validate_file_size(path),
         :ok <- validate_file_extension(original_name),
         {:ok, filename} <- generate_unique_filename(original_name),
         :ok <- ensure_bucket_exists(),
         {:ok, _} <- upload_to_minio(path, filename) do
      {:ok, public_url(filename)}
    end
  end

  @doc """
  Gera uma URL pública para um arquivo no MinIO.
  """
  def public_url(filename) when is_binary(filename) do
    "#{@base_url}/#{@bucket}/#{filename}"
  end

  @doc """
  Remove um arquivo do MinIO.
  """
  def delete_file(filename) when is_binary(filename) do
    ExAws.S3.delete_object(@bucket, filename)
    |> ExAws.request()
  end

  @doc """
  Lista todos os arquivos no bucket.
  """
  def list_files do
    ExAws.S3.list_objects(@bucket)
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{contents: contents}}} ->
        files = contents
        |> Enum.map(& &1.key)
        |> Enum.filter(&is_image_file?/1)
        |> Enum.map(&public_url/1)
        {:ok, files}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifica se um arquivo existe no MinIO.
  """
  def file_exists?(filename) when is_binary(filename) do
    ExAws.S3.head_object(@bucket, filename)
    |> ExAws.request()
    |> case do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Funções privadas

  defp validate_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        :ok
      {:ok, %{size: _size}} ->
        {:error, "Arquivo muito grande. Máximo permitido: #{@max_file_size} bytes"}
      {:error, reason} ->
        {:error, "Erro ao verificar tamanho do arquivo: #{inspect(reason)}"}
    end
  end

  defp validate_file_extension(filename) do
    extension = filename
    |> String.downcase()
    |> String.split(".")
    |> List.last()
    |> case do
      nil -> ""
      ext -> ".#{ext}"
    end

    case extension in @allowed_extensions do
      true -> :ok
      false -> {:error, "Extensão não permitida: '#{extension}'. Permitidas: #{Enum.join(@allowed_extensions, ", ")}"}
    end
  end

  defp generate_unique_filename(original_name) do
    extension = Path.extname(original_name)
    base_name = Path.basename(original_name, extension)
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    # Sanitizar o nome base
    sanitized_base = base_name
    |> String.replace(~r/[^a-zA-Z0-9\-_]/, "_")
    |> String.slice(0, 50)

    filename = "#{sanitized_base}_#{timestamp}_#{unique_id}#{extension}"
    {:ok, filename}
  end

  defp ensure_bucket_exists do
    # Para desenvolvimento, assumir que o bucket existe
    # Em produção, criar o bucket manualmente no MinIO
    :ok
  end

  defp upload_to_minio(path, filename) do
    file_content = File.read!(path)
    content_type = MIME.from_path(filename)

    ExAws.S3.put_object(@bucket, filename, file_content, [
      content_type: content_type,
      acl: :public_read
    ])
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, filename}
      {:error, reason} -> {:error, "Erro ao fazer upload: #{inspect(reason)}"}
    end
  end

  defp is_image_file?(filename) do
    extension = Path.extname(filename) |> String.downcase()
    extension in @allowed_extensions
  end
end
