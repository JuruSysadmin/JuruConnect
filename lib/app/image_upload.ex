defmodule App.ImageUpload do
  @moduledoc """
  Módulo para gerenciar uploads de imagens localmente.

  Salva imagens na pasta priv/static/images/ e retorna URLs públicas.
  """

  require Logger

  @images_dir "priv/static/images"
  @max_file_size 5_000_000 # 5MB
  @allowed_extensions ~w(.jpg .jpeg .png .gif .webp)
  @allowed_mime_types ~w(image/jpeg image/png image/gif image/webp)

  @doc """
  Salva um arquivo de imagem localmente e retorna a URL pública.

  ## Parâmetros
  - `path`: Caminho temporário do arquivo
  - `original_name`: Nome original do arquivo

  ## Retorno
  - `{:ok, url}`: URL pública da imagem
  - `{:error, reason}`: Erro no upload
  """
  def upload_image(path, original_name) when is_binary(path) and is_binary(original_name) do
    with :ok <- validate_file_size(path),
         :ok <- validate_file_extension_simple(original_name),
         {:ok, filename} <- generate_unique_filename(original_name),
         {:ok, _} <- save_file(path, filename) do
      {:ok, public_url(filename)}
    end
  end

  @doc """
  Gera uma URL pública para uma imagem.
  """
  def public_url(filename) when is_binary(filename) do
    "/images/#{filename}"
  end

  @doc """
  Remove uma imagem do sistema de arquivos.
  """
  def delete_image(filename) when is_binary(filename) do
    file_path = Path.join(@images_dir, filename)

    case File.exists?(file_path) do
      true -> File.rm(file_path)
      false -> {:error, :not_found}
    end
  end

  @doc """
  Lista todas as imagens disponíveis.
  """
  def list_images do
    case File.ls(@images_dir) do
      {:ok, files} ->
        images = files
        |> Enum.filter(&is_image_file?/1)
        |> Enum.map(&public_url/1)
        {:ok, images}
      {:error, reason} ->
        {:error, reason}
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

  defp validate_file_extension_simple(filename) do
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

  defp validate_mime_type(path) do
    case :filelib.is_file(path) do
      true ->
        case :mimerl.filename(path) do
          {mime_type, _} when mime_type in @allowed_mime_types ->
            :ok
          {mime_type, _} when mime_type == "application/octet-stream" ->
            validate_by_extension(path)
          {mime_type, _} ->
            {:error, "Tipo MIME não permitido: #{mime_type}. Permitidos: #{Enum.join(@allowed_mime_types, ", ")}"}
          mime_type when mime_type == "application/octet-stream" ->
            validate_by_extension(path)
          mime_type when is_binary(mime_type) and mime_type in @allowed_mime_types ->
            :ok
          :undefined ->
            validate_by_extension(path)
          _ ->
            {:error, "Tipo MIME não permitido (indeterminado ou formato desconhecido)."}
        end
      false ->
        {:error, "Arquivo não encontrado"}
    end
  end

  defp validate_by_extension(path) do
    extension = Path.extname(path) |> String.downcase()

    case extension in @allowed_extensions do
      true -> :ok
      false -> {:error, "Extensão não permitida: #{extension}. Permitidas: #{Enum.join(@allowed_extensions, ", ")}"}
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

  defp save_file(source_path, filename) do
    # Garantir que o diretório existe
    File.mkdir_p!(@images_dir)

    destination_path = Path.join(@images_dir, filename)

    case File.cp(source_path, destination_path) do
      :ok -> {:ok, destination_path}
      {:error, reason} -> {:error, "Erro ao salvar arquivo: #{inspect(reason)}"}
    end
  end

  defp is_image_file?(filename) do
    extension = Path.extname(filename) |> String.downcase()
    extension in @allowed_extensions
  end
end
