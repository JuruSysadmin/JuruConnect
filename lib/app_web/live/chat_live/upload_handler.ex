defmodule AppWeb.ChatLive.UploadHandler do
  @moduledoc """
  Manipulador de uploads para o chat em tempo real.

  Este módulo contém toda a lógica relacionada ao processamento de uploads
  de arquivos (imagens, documentos e áudio) extraída do AppWeb.ChatLive
  para melhorar a organização e eliminar anti-padrões.

  ## Funcionalidades
  - Upload de imagens (JPG, PNG, GIF)
  - Upload de documentos (PDF, Word, Excel, PowerPoint)
  - Gravação e upload de áudio
  - Validação de tipos e tamanhos
  - Geração de nomes únicos
  - Gestão de arquivos temporários

  ## Anti-padrões Corrigidos
  - Long parameter list: Parâmetros agrupados em structs
  - Primitive obsession: Tipos definidos ao invés de strings
  - Complex extractions: Funções multi-cláusula com pattern matching
  - Comments overuse: Logs limpos e informativos
  """

  require Logger

  @type upload_type :: :image | :document | :audio
  @type upload_result :: {:ok, String.t()} | {:error, String.t()}
  @type validation_result :: {:ok, Phoenix.LiveView.Socket.t()} | {:error, String.t()}

  defmodule UploadParams do
    @moduledoc """
    Estrutura para agrupar parâmetros de upload relacionados.
    Elimina o anti-padrão Long parameter list.
    """

    @type t :: %__MODULE__{
      data: binary() | nil,
      filename: String.t(),
      size: integer(),
      mime_type: String.t(),
      duration: integer() | nil
    }

    defstruct [:data, :filename, :size, :mime_type, :duration]
  end

  # ========================================
  # IMAGE UPLOAD
  # ========================================

  @doc """
  Processa upload de imagem usando pattern matching assertivo.
  """
  @spec process_image_upload(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def process_image_upload(socket) do
    case socket.assigns.uploads.image.entries do
      [] ->
        Logger.debug("Nenhuma imagem para upload")
        nil

      entries ->
        Logger.debug("Processando upload de imagem - #{length(entries)} entries")
        process_image_entries(socket, entries)
    end
  end

  @doc """
  Valida entrada de imagem usando pattern matching assertivo.
  """
  @spec validate_image_entry(map(), Phoenix.LiveView.Socket.t()) :: validation_result()
  def validate_image_entry(%{valid?: true} = entry, socket) do
    {:ok,
     socket
     |> Phoenix.LiveView.assign(:message_error, nil)
     |> Phoenix.LiveView.put_flash(:info, "Imagem selecionada: #{entry.client_name}")
    }
  end

  def validate_image_entry(%{valid?: false, errors: errors} = _entry, socket) do
    error_message = format_upload_error(errors)
    {:ok, Phoenix.LiveView.put_flash(socket, :error, error_message)}
  end

  # ========================================
  # DOCUMENT UPLOAD
  # ========================================

  @doc """
  Processa upload de documento usando pattern matching assertivo.
  """
  @spec process_document_upload(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def process_document_upload(socket) do
    case socket.assigns.uploads.document.entries do
      [] ->
        Logger.debug("Nenhum documento para upload")
        nil

      entries ->
        Logger.debug("Processando upload de documento - #{length(entries)} entries")
        process_document_entries(socket, entries)
    end
  end

  @doc """
  Valida entrada de documento usando pattern matching assertivo.
  """
  @spec validate_document_entry(map(), Phoenix.LiveView.Socket.t()) :: validation_result()
  def validate_document_entry(entry, socket) do
    cond do
      entry.valid? and validate_document_type(entry.client_name) ->
        handle_valid_document(entry, socket)

      not entry.valid? ->
        handle_invalid_document(entry, socket)

      true ->
        {:ok, Phoenix.LiveView.put_flash(socket, :error, "Tipo de documento não suportado")}
    end
  end

  # ========================================
  # AUDIO UPLOAD
  # ========================================

  @doc """
  Processa áudio gravado usando parâmetros estruturados.
  Elimina Long parameter list agrupando parâmetros relacionados.
  """
  @spec process_recorded_audio(Phoenix.LiveView.Socket.t(), map()) :: upload_result()
  def process_recorded_audio(socket, audio_params) do
    upload_params = %UploadParams{
      data: audio_params["audio_data"],
      filename: generate_audio_filename(audio_params["mime_type"]),
      mime_type: audio_params["mime_type"] || "audio/webm",
      duration: audio_params["duration"] || 0
    }

    try do
      audio_url = upload_audio_from_params(upload_params)

      message_params = build_audio_message_params(socket, upload_params, audio_url)

      case App.Chat.create_message(message_params) do
        {:ok, message} ->
          broadcast_audio_message(socket, message)
          {:ok, socket |> assign_audio_success()}

        {:error, _changeset} ->
          {:error, "Falha ao salvar mensagem de áudio"}
      end
    rescue
      error ->
        Logger.error("Error processing recorded audio: #{inspect(error)}")
        {:error, "Erro interno ao processar áudio"}
    end
  end

  @doc """
  Formata texto de mensagem de áudio usando pattern matching assertivo.
  """
  @spec format_audio_message_text(map()) :: String.t()
  def format_audio_message_text(%{"duration" => duration}) when is_integer(duration) do
    minutes = div(duration, 60)
    seconds = rem(duration, 60)
    "Áudio #{String.pad_leading("#{minutes}", 2, "0")}:#{String.pad_leading("#{seconds}", 2, "0")}"
  end

  def format_audio_message_text(_), do: "Mensagem de áudio"

  # ========================================
  # UPLOAD CANCELLATION
  # ========================================

  @doc """
  Cancela upload por referência usando pattern matching assertivo.
  """
  @spec cancel_upload_by_ref(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def cancel_upload_by_ref(socket, ref) do
    case socket.assigns.uploads do
      %{image: %{entries: image_entries}, document: %{entries: document_entries}} ->
        cancel_upload_by_type(socket, ref, image_entries, document_entries)
      _ ->
        socket
    end
  end

  # ========================================
  # PRIVATE FUNCTIONS
  # ========================================

  # Pattern matching assertivo para processamento de imagens
  defp process_image_entries(socket, _entries) do
    result = Phoenix.LiveView.consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
      process_single_image_upload(path, entry)
    end)

    Logger.debug("Resultado do consume_uploaded_entries: #{inspect(result)}")
    extract_upload_url_from_result(result)
  end

  # Processamento individual de imagem com tratamento de erro
  defp process_single_image_upload(path, entry) do
    filename = generate_unique_filename(entry.client_name)
    Logger.debug("Upload de imagem: #{entry.client_name} -> #{filename}")

    case App.Minio.upload_file(path, filename) do
      {:ok, url} ->
        Logger.info("Imagem enviada com sucesso: #{url}")
        {:ok, url}
      {:error, reason} ->
        Logger.error("Falha no upload da imagem: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  # Pattern matching assertivo para processamento de documentos
  defp process_document_entries(socket, _entries) do
    result = Phoenix.LiveView.consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
      process_single_document_upload(path, entry)
    end)

    Logger.debug("Resultado do consume_uploaded_entries: #{inspect(result)}")
    extract_upload_url_from_result(result)
  end

  # Processamento individual de documento
  defp process_single_document_upload(path, entry) do
    filename = generate_unique_filename(entry.client_name)
    Logger.debug("Upload de documento: #{entry.client_name} -> #{filename}")

    case App.Minio.upload_file(path, filename) do
      {:ok, url} ->
        Logger.info("Documento enviado com sucesso: #{url}")
        {:ok, url}
      {:error, reason} ->
        Logger.error("Falha no upload do documento: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  # Extração assertiva de URL do resultado
  defp extract_upload_url_from_result(result) do
    case List.first(result) do
      url when is_binary(url) and url != "" and url != nil -> url
      {:ok, url} when is_binary(url) -> url
      _ -> nil
    end
  end

  # Validação de documento válido
  defp handle_valid_document(entry, socket) do
    document_type = AppWeb.ChatLive.Helpers.get_document_type(entry.client_name)

    {:ok,
     socket
     |> Phoenix.LiveView.assign(:message_error, nil)
     |> Phoenix.LiveView.put_flash(:info, "#{document_type} selecionado: #{entry.client_name}")
    }
  end

  # Tratamento de documento inválido
  defp handle_invalid_document(entry, socket) do
    error_message = AppWeb.ChatLive.Helpers.format_document_upload_error(entry.errors)
    {:ok, Phoenix.LiveView.put_flash(socket, :error, error_message)}
  end

  # Validação de tipo de documento
  defp validate_document_type(filename) when is_binary(filename) do
    App.Minio.supported_file_type?(filename)
  end
  defp validate_document_type(_), do: false

  # Upload de áudio a partir de parâmetros estruturados
  defp upload_audio_from_params(%UploadParams{} = params) do
    Logger.debug("Processando upload de áudio: #{params.mime_type}")

    file_extension = extract_audio_file_extension(params.mime_type)
    filename = generate_audio_filename(file_extension)

    binary_data = Base.decode64!(params.data)
    temp_path = create_temp_audio_file(filename, binary_data)

    case App.Minio.upload_file(temp_path, filename) do
      {:ok, url} ->
        File.rm(temp_path)
        Logger.info("Áudio enviado: #{url}")
        url
      {:error, reason} ->
        File.rm(temp_path)
        Logger.error("Falha no upload do áudio: #{inspect(reason)}")
        raise "Falha no upload de áudio: #{inspect(reason)}"
    end
  end

  # Construção de parâmetros de mensagem de áudio
  defp build_audio_message_params(socket, upload_params, audio_url) do
    %{
      text: format_audio_message_text(%{"duration" => upload_params.duration}),
      sender_id: socket.assigns.current_user_id,
      sender_name: socket.assigns.current_user_name,
      order_id: socket.assigns.order_id,
      tipo: :audio,
      audio_url: audio_url,
      audio_duration: upload_params.duration,
      audio_mime_type: upload_params.mime_type,
      status: :sent
    }
  end

  # Broadcast de mensagem de áudio
  defp broadcast_audio_message(socket, message) do
    topic = "order:#{socket.assigns.order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
  end

  # Atribuição de sucesso de áudio
  defp assign_audio_success(socket) do
    socket
    |> Phoenix.LiveView.assign(:is_recording_audio, false)
    |> Phoenix.LiveView.put_flash(:info, "Áudio enviado com sucesso!")
  end

  # Geração de nome de arquivo de áudio usando pattern matching
  defp generate_audio_filename(extension_or_mime) do
    extension = extract_audio_file_extension(extension_or_mime)
    timestamp = System.system_time(:millisecond)
    uuid = UUID.uuid4() |> String.slice(0, 8)
    "audio_#{timestamp}_#{uuid}.#{extension}"
  end

  # Pattern matching para extensões de áudio
  defp extract_audio_file_extension("audio/webm" <> _), do: "webm"
  defp extract_audio_file_extension("audio/mp4"), do: "mp4"
  defp extract_audio_file_extension("audio/wav"), do: "wav"
  defp extract_audio_file_extension("audio/mp3"), do: "mp3"
  defp extract_audio_file_extension("webm"), do: "webm"
  defp extract_audio_file_extension("mp4"), do: "mp4"
  defp extract_audio_file_extension("wav"), do: "wav"
  defp extract_audio_file_extension("mp3"), do: "mp3"
  defp extract_audio_file_extension(_), do: "webm"

  # Criação de arquivo temporário de áudio
  defp create_temp_audio_file(filename, binary_data) do
    temp_path = System.tmp_dir!() |> Path.join(filename)

    case File.write(temp_path, binary_data) do
      :ok -> temp_path
      {:error, reason} ->
        raise "Falha ao criar arquivo temporário: #{reason}"
    end
  end

  # Geração de nome único para arquivo
  defp generate_unique_filename(original_name) do
    timestamp = System.system_time(:millisecond)
    uuid = UUID.uuid4() |> String.slice(0, 8)
    extension = Path.extname(original_name)
    base_name = Path.basename(original_name, extension) |> String.slice(0, 20)

    "#{timestamp}_#{uuid}_#{base_name}#{extension}"
  end

  # Cancelamento de upload por tipo usando pattern matching
  defp cancel_upload_by_type(socket, ref, image_entries, document_entries) do
    cond do
      Enum.any?(image_entries, &(&1.ref == ref)) ->
        Phoenix.LiveView.cancel_upload(socket, :image, ref)
      Enum.any?(document_entries, &(&1.ref == ref)) ->
        Phoenix.LiveView.cancel_upload(socket, :document, ref)
      true ->
        socket
    end
  end

  # Formatação de erros de upload usando pattern matching assertivo
  defp format_upload_error(errors) do
    Enum.map_join(errors, ", ", fn
      :too_large -> "Arquivo muito grande (máximo 5MB)"
      :not_accepted -> "Tipo de arquivo não aceito (apenas JPG, PNG, GIF)"
      :too_many_files -> "Apenas uma imagem por vez"
      :external_client_failure -> "Falha no upload"
      error -> "Erro: #{inspect(error)}"
    end)
  end
end
