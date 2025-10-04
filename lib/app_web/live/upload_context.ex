defmodule AppWeb.UploadContext do
  @moduledoc """
  Contexto para lógica de negócio relacionada a uploads de arquivos.
  
  Este módulo encapsula toda a lógica de negócio para:
  - Configuração de uploads
  - Validação de arquivos
  - Processamento de uploads
  - Gerenciamento de estados de upload
  - Feedback visual para drag & drop
  """

  alias AppWeb.ChatConfig

  @doc """
  Configura upload para um socket LiveView.
  
  ## Parâmetros
  - `socket`: Socket do LiveView
  - `upload_type`: Tipo do upload (:image)
  
  ## Retorno
  - `socket` - Socket com upload configurado
  """
  def configure_upload(socket, upload_type \\ :image) do
    Phoenix.LiveView.allow_upload(socket, upload_type,
      accept: ChatConfig.get_config_value(:upload, :allowed_image_types),
      max_entries: ChatConfig.get_config_value(:upload, :max_entries),
      max_file_size: ChatConfig.get_config_value(:upload, :max_file_size),
      auto_upload: ChatConfig.get_config_value(:upload, :auto_upload)
    )
  end

  @doc """
  Valida se um arquivo pode ser enviado.
  
  ## Parâmetros
  - `entry`: Entrada do upload
  - `max_file_size`: Tamanho máximo permitido
  
  ## Retorno
  - `{:ok, entry}` - Arquivo válido
  - `{:error, reason}` - Arquivo inválido
  """
  def validate_upload_entry(entry, max_file_size \\ nil) do
    max_size = max_file_size || ChatConfig.get_config_value(:upload, :max_file_size)
    
    cond do
      entry.client_size > max_size ->
        {:error, "Arquivo muito grande. Máximo: #{format_file_size(max_size)}"}
      
      not valid_file_type?(entry.client_type) ->
        {:error, "Tipo de arquivo não permitido"}
      
      true ->
        {:ok, entry}
    end
  end

  @doc """
  Processa uma entrada de upload e retorna informações estruturadas.
  
  ## Parâmetros
  - `path`: Caminho temporário do arquivo
  - `entry`: Entrada do upload
  
  ## Retorno
  - `{:ok, file_info}` - Informações do arquivo processado
  - `{:error, reason}` - Erro no processamento
  """
  def process_upload_entry(%{path: path}, entry) do
    with {:ok, temp_path} <- create_temp_file(path, entry.client_name) do
      {:ok, %{
        temp_path: temp_path,
        original_filename: entry.client_name,
        file_size: entry.client_size,
        mime_type: entry.client_type,
        pending_upload: true
      }}
    end
  end

  @doc """
  Obtém estado de drag & drop baseado em uploads.
  
  ## Parâmetros
  - `socket`: Socket do LiveView
  
  ## Retorno
  - `drag_state` - Estado do drag & drop ("idle", "dragging", "dropped")
  """
  def get_drag_drop_state(socket) do
    case socket.assigns.uploads do
      %{image: %{entries: []}} -> "idle"
      %{image: %{entries: [_ | _]}} -> "dragging"
      _ -> "idle"
    end
  end

  @doc """
  Obtém classes CSS para overlay de drag & drop.
  
  ## Parâmetros
  - `drag_state`: Estado do drag & drop
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_drag_overlay_classes(drag_state) do
    base_classes = "fixed inset-0 bg-gradient-to-br from-blue-500/30 via-blue-400/20 to-blue-600/30 backdrop-blur-md flex items-center justify-center pointer-events-none transition-all duration-300 z-50"
    
    case drag_state do
      "dragging" -> base_classes <> " opacity-100"
      _ -> base_classes <> " opacity-0"
    end
  end

  @doc """
  Obtém classes CSS para conteúdo de drag & drop.
  
  ## Parâmetros
  - `drag_state`: Estado do drag & drop
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_drag_content_classes(drag_state) do
    base_classes = "bg-white/95 backdrop-blur-lg rounded-3xl p-8 shadow-2xl border border-blue-200/50 transition-all duration-300 max-w-sm mx-4"
    
    case drag_state do
      "dragging" -> base_classes <> " scale-100"
      _ -> base_classes <> " scale-95"
    end
  end

  @doc """
  Obtém classes CSS para preview de upload.
  
  ## Parâmetros
  - `entry`: Entrada do upload
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_upload_preview_classes(entry) do
    base_classes = "upload-preview-container rounded-lg border border-gray-200 shadow-md hover:shadow-lg transition-shadow duration-200 overflow-hidden bg-gray-100"
    
    if entry.progress >= 100 do
      base_classes <> " upload-complete"
    else
      base_classes <> " upload-pending"
    end
  end

  @doc """
  Obtém classes CSS para barra de progresso.
  
  ## Parâmetros
  - `entry`: Entrada do upload
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_progress_bar_classes(entry) do
    base_classes = "h-full bg-blue-500 transition-all duration-300"
    
    if entry.progress >= 100 do
      base_classes <> " w-full"
    else
      base_classes <> " w-0"
    end
  end

  @doc """
  Formata tamanho de arquivo para exibição.
  
  ## Parâmetros
  - `bytes`: Tamanho em bytes
  
  ## Retorno
  - `formatted_size` - Tamanho formatado (ex: "2.5 MB")
  """
  def format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  @doc """
  Obtém tipos de arquivo permitidos.
  
  ## Retorno
  - `allowed_types` - Lista de tipos MIME permitidos
  """
  def get_allowed_file_types do
    ChatConfig.get_config_value(:upload, :allowed_image_types)
  end

  @doc """
  Obtém tamanho máximo de arquivo.
  
  ## Retorno
  - `max_size` - Tamanho máximo em bytes
  """
  def get_max_file_size do
    ChatConfig.get_config_value(:upload, :max_file_size)
  end

  @doc """
  Obtém número máximo de entradas de upload.
  
  ## Retorno
  - `max_entries` - Número máximo de arquivos
  """
  def get_max_entries do
    ChatConfig.get_config_value(:upload, :max_entries)
  end

  # Funções privadas

  defp valid_file_type?(mime_type) do
    allowed_types = get_allowed_file_types()
    mime_type in allowed_types
  end

  defp create_temp_file(source_path, original_name) do
    temp_dir = Path.join(System.tmp_dir(), ChatConfig.get_config_value(:upload, :temp_dir_prefix))
    File.mkdir_p!(temp_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    extension = Path.extname(original_name)
    temp_filename = "upload_#{timestamp}_#{unique_id}#{extension}"
    temp_path = Path.join(temp_dir, temp_filename)

    case File.cp(source_path, temp_path) do
      :ok -> {:ok, temp_path}
      {:error, reason} -> {:error, "Failed to create temp file: #{reason}"}
    end
  end
end
