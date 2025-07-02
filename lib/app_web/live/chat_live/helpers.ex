defmodule AppWeb.ChatLive.Helpers do
  @moduledoc """
  Funções auxiliares para o chat em tempo real.

  Este módulo contém funções puras de formatação, validação e utilitários
  extraídas do AppWeb.ChatLive para melhorar a organização e manutenibilidade.

  ## Seções
  - Message Validation: Verificações de tipo de mensagem
  - Formatting: Formatação de dados para exibição
  - UI Styling: Classes CSS e cores para interface
  - File Handling: Manipulação de arquivos e documentos
  - Utilities: Funções utilitárias gerais
  """

  @type message_status :: :sent | :delivered | :read | :system
  @type message_type :: :mensagem | :imagem | :documento | :audio | :system_notification

  # ========================================
  # MESSAGE VALIDATION
  # ========================================

  @doc """
  Verifica se a mensagem é do sistema.
  """
  @spec is_system_message?(map()) :: boolean()
  def is_system_message?(%{is_system: true}), do: true
  def is_system_message?(_), do: false

  @doc """
  Verifica se é uma notificação de entrada.
  """
  @spec is_join_notification?(map()) :: boolean()
  def is_join_notification?(%{notification_type: "join"}), do: true
  def is_join_notification?(_), do: false

  @doc """
  Verifica se é uma mensagem de resposta.
  """
  @spec is_reply_message?(map()) :: boolean()
  def is_reply_message?(%{is_reply: true, reply_to: reply_to}) when not is_nil(reply_to), do: true
  def is_reply_message?(%{reply_to: reply_to}) when not is_nil(reply_to), do: true
  def is_reply_message?(_), do: false

  @doc """
  Verifica se é uma mensagem de áudio.
  """
  @spec is_audio_message?(map()) :: boolean()
  def is_audio_message?(%{tipo: "audio", audio_url: url}) when not is_nil(url), do: true
  def is_audio_message?(_), do: false

  @doc """
  Verifica se a mensagem tem menções.
  """
  @spec has_mentions?(map()) :: boolean()
  def has_mentions?(%{has_mentions: true}), do: true
  def has_mentions?(_), do: false

  @doc """
  Verifica se a mensagem tem imagem.
  """
  @spec has_image?(map()) :: boolean()
  def has_image?(%{image_url: url}) when not is_nil(url) and url != "", do: true
  def has_image?(_), do: false

  @doc """
  Verifica se a mensagem tem documento.
  """
  @spec has_document?(map()) :: boolean()
  def has_document?(%{document_url: url}) when not is_nil(url) and url != "", do: true
  def has_document?(_), do: false

  @doc """
  Verifica se a mensagem tem preview de link.
  """
  @spec has_link_preview?(map()) :: boolean()
  def has_link_preview?(%{link_preview_url: url}) when not is_nil(url) and url != "", do: true
  def has_link_preview?(_), do: false

  @doc """
  Verifica se é uma mensagem original (não é resposta).
  """
  @spec is_original_message?(map()) :: boolean()
  def is_original_message?(%{is_reply: false, reply_to: nil}), do: true
  def is_original_message?(%{reply_to: nil}), do: true
  def is_original_message?(_), do: false

  # ========================================
  # FORMATTING
  # ========================================

  @doc """
  Formata valores monetários.
  """
  @spec format_currency(String.t() | number()) :: String.t()
  def format_currency(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {float_amount, _} -> :erlang.float_to_binary(float_amount, decimals: 2)
      :error -> amount
    end
  end

  def format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  def format_currency(_), do: "0.00"

  @doc """
  Formata datas no formato brasileiro.
  """
  @spec format_date(String.t()) :: String.t()
  def format_date(date_string) when is_binary(date_string) and date_string != "" do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        "#{String.pad_leading("#{datetime.day}", 2, "0")}/#{String.pad_leading("#{datetime.month}", 2, "0")}/#{datetime.year}"
      _ ->
        date_string
    end
  end

  def format_date(_), do: "Data não disponível"

  @doc """
  Formata horários no formato HH:MM.
  """
  @spec format_time(DateTime.t() | any()) :: String.t()
  def format_time(%DateTime{} = datetime) do
    "#{String.pad_leading("#{datetime.hour}", 2, "0")}:#{String.pad_leading("#{datetime.minute}", 2, "0")}"
  end

  def format_time(_), do: "Hora não disponível"

  @doc """
  Formata lista de usuários digitando.
  """
  @spec format_typing_users(MapSet.t()) :: String.t()
  def format_typing_users(typing_users) do
    user_list = MapSet.to_list(typing_users)

    case length(user_list) do
      0 -> ""
      1 -> List.first(user_list)
      2 -> "#{Enum.at(user_list, 0)} e #{Enum.at(user_list, 1)}"
      _ -> "#{length(user_list)} usuários"
    end
  end

  @doc """
  Formata tamanho de arquivos em bytes, KB ou MB.
  """
  @spec format_file_size(integer()) :: String.t()
  def format_file_size(size) when is_integer(size) do
    cond do
      size >= 1_048_576 -> "#{Float.round(size / 1_048_576, 1)}MB"
      size >= 1_024 -> "#{Float.round(size / 1_024, 1)}KB"
      true -> "#{size}B"
    end
  end

  def format_file_size(_), do: "Tamanho desconhecido"

  @doc """
  Formata erros de upload de imagens.
  """
  @spec format_upload_error(list()) :: String.t()
  def format_upload_error(errors) do
    Enum.map_join(errors, ", ", fn
      :too_large -> "Arquivo muito grande (máximo 5MB)"
      :not_accepted -> "Tipo de arquivo não aceito (apenas JPG, PNG, GIF)"
      :too_many_files -> "Apenas uma imagem por vez"
      :external_client_failure -> "Falha no upload"
      error -> "Erro: #{inspect(error)}"
    end)
  end

  @doc """
  Formata erros de upload de documentos.
  """
  @spec format_document_upload_error(list()) :: String.t()
  def format_document_upload_error(errors) do
    Enum.map_join(errors, ", ", fn
      :too_large -> "Documento muito grande (máximo 25MB)"
      :not_accepted -> "Tipo de arquivo não aceito (apenas PDF, Word, Excel, PowerPoint)"
      :too_many_files -> "Apenas um documento por vez"
      :external_client_failure -> "Falha no upload"
      error -> "Erro: #{inspect(error)}"
    end)
  end

  @doc """
  Formata contador de respostas em thread.
  """
  @spec format_thread_reply_counter(integer()) :: String.t()
  def format_thread_reply_counter(reply_count) when is_integer(reply_count) do
    case reply_count do
      1 -> "1 resposta"
      count when count > 1 -> "#{count} respostas"
      _ -> "Thread"
    end
  end

  def format_thread_reply_counter(_), do: "Thread"

  @doc """
  Formata erros de changeset.
  """
  @spec format_errors(list()) :: String.t()
  def format_errors(errors) do
    errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  # ========================================
  # UI STYLING
  # ========================================

  @doc """
  Retorna inicial do usuário para avatar.
  """
  @spec get_user_initial(String.t()) :: String.t()
  def get_user_initial(user) when is_binary(user) and user != "" do
    user |> String.first() |> String.upcase()
  end

  def get_user_initial(_), do: "U"

  @doc """
  Retorna classes CSS para status de pedido.
  """
  @spec get_status_class(String.t()) :: String.t()
  def get_status_class(status) do
    base_classes = "px-3 py-1.5 text-xs font-semibold rounded-full border shadow-sm"

    case String.downcase(status || "") do
      "ativo" -> "#{base_classes} bg-green-100 text-green-800 border-green-200"
      "pendente" -> "#{base_classes} bg-yellow-100 text-yellow-800 border-yellow-200"
      "cancelado" -> "#{base_classes} bg-red-100 text-red-800 border-red-200"
      "concluído" -> "#{base_classes} bg-blue-100 text-blue-800 border-blue-200"
      _ -> "#{base_classes} bg-gray-100 text-gray-800 border-gray-200"
    end
  end

  @doc """
  Retorna classes CSS para indicador de conexão.
  """
  @spec get_connection_indicator_class(boolean()) :: String.t()
  def get_connection_indicator_class(connected) do
    base_classes = "w-1.5 h-1.5 rounded-full mr-1.5"

    if connected,
      do: "#{base_classes} bg-green-500 animate-pulse",
      else: "#{base_classes} bg-red-500"
  end

  @doc """
  Retorna classes CSS para texto de conexão.
  """
  @spec get_connection_text_class(boolean()) :: String.t()
  def get_connection_text_class(connected) do
    if connected, do: "text-green-600", else: "text-red-600"
  end

  @doc """
  Retorna cores do usuário baseadas em hash do ID e nome.
  """
  @spec get_user_color(String.t(), String.t()) :: map()
  def get_user_color(user_id, user_name) do
    hash = :crypto.hash(:md5, "#{user_id}#{user_name}")
           |> :binary.bin_to_list()
           |> Enum.take(3)
           |> Enum.sum()

    colors = [
      %{
        bg: "bg-gradient-to-br from-slate-500 to-slate-600",
        light: "bg-gradient-to-br from-slate-100 to-slate-200 border-l-4 border-slate-400",
        avatar: "bg-gradient-to-br from-slate-500 to-slate-600"
      },
      %{
        bg: "bg-gradient-to-br from-gray-500 to-gray-600",
        light: "bg-gradient-to-br from-gray-100 to-gray-200 border-l-4 border-gray-400",
        avatar: "bg-gradient-to-br from-gray-500 to-gray-600"
      },
      %{
        bg: "bg-gradient-to-br from-zinc-500 to-zinc-600",
        light: "bg-gradient-to-br from-zinc-100 to-zinc-200 border-l-4 border-zinc-400",
        avatar: "bg-gradient-to-br from-zinc-500 to-zinc-600"
      },
      %{
        bg: "bg-gradient-to-br from-stone-500 to-stone-600",
        light: "bg-gradient-to-br from-stone-100 to-stone-200 border-l-4 border-stone-400",
        avatar: "bg-gradient-to-br from-stone-500 to-stone-600"
      },
      %{
        bg: "bg-gradient-to-br from-neutral-500 to-neutral-600",
        light: "bg-gradient-to-br from-neutral-100 to-neutral-200 border-l-4 border-neutral-400",
        avatar: "bg-gradient-to-br from-neutral-500 to-neutral-600"
      },
      %{
        bg: "bg-gradient-to-br from-slate-600 to-gray-700",
        light: "bg-gradient-to-br from-slate-100 to-gray-200 border-l-4 border-slate-500",
        avatar: "bg-gradient-to-br from-slate-600 to-gray-700"
      },
      %{
        bg: "bg-gradient-to-br from-gray-600 to-zinc-700",
        light: "bg-gradient-to-br from-gray-100 to-zinc-200 border-l-4 border-gray-500",
        avatar: "bg-gradient-to-br from-gray-600 to-zinc-700"
      },
      %{
        bg: "bg-gradient-to-br from-zinc-600 to-stone-700",
        light: "bg-gradient-to-br from-zinc-100 to-stone-200 border-l-4 border-zinc-500",
        avatar: "bg-gradient-to-br from-zinc-600 to-stone-700"
      }
    ]

    color_index = rem(hash, length(colors))
    Enum.at(colors, color_index)
  end

  @doc """
  Retorna cores de mensagem baseadas no remetente.
  """
  @spec get_message_color(String.t(), String.t(), String.t()) :: String.t()
  def get_message_color(sender_id, current_user_id, _sender_name) do
    if sender_id == current_user_id do
      "rounded-br-sm text-gray-800" <> " " <> "bg-[#DCF8C6]"
    else
      "bg-white border border-gray-200 text-gray-900 rounded-bl-sm shadow-sm"
    end
  end

  @doc """
  Retorna cores de avatar baseadas no usuário.
  """
  @spec get_avatar_color(String.t(), String.t()) :: String.t()
  def get_avatar_color(user_id, user_name) do
    user_color = get_user_color(user_id, user_name)
    user_color.avatar
  end

  @doc """
  Retorna cores de nome de usuário.
  """
  @spec get_username_color(String.t(), String.t()) :: String.t()
  def get_username_color(user_id, user_name) do
    hash = :crypto.hash(:md5, "#{user_id}#{user_name}")
           |> :binary.bin_to_list()
           |> Enum.take(2)
           |> Enum.sum()

    username_colors = [
      "text-slate-600",
      "text-gray-600",
      "text-zinc-600",
      "text-stone-600",
      "text-neutral-600",
      "text-slate-700",
      "text-gray-700",
      "text-zinc-700"
    ]

    color_index = rem(hash, length(username_colors))
    Enum.at(username_colors, color_index)
  end

  @doc """
  Retorna cores para respostas em thread.
  """
  @spec get_thread_reply_color(String.t(), String.t(), String.t()) :: String.t()
  def get_thread_reply_color(sender_id, current_user_id, _sender_name) do
    if sender_id == current_user_id do
      "bg-gradient-to-br from-green-50 to-green-100 border-l-4 border-[#25D366]"
    else
      "bg-gray-50 border-l-4 border-gray-300"
    end
  end

  # ========================================
  # FILE HANDLING
  # ========================================

  @doc """
  Gera nome único para arquivo.
  """
  @spec generate_unique_filename(String.t()) :: String.t()
  def generate_unique_filename(original_name) do
    timestamp = System.system_time(:millisecond)
    uuid = UUID.uuid4() |> String.slice(0, 8)
    extension = Path.extname(original_name)
    base_name = Path.basename(original_name, extension) |> String.slice(0, 20)

    "#{timestamp}_#{uuid}_#{base_name}#{extension}"
  end

  @doc """
  Extrai nome do arquivo da URL.
  """
  @spec extract_filename_from_url(String.t()) :: String.t()
  def extract_filename_from_url(url) when is_binary(url) do
    url |> String.split("/") |> List.last() || "documento"
  end
  def extract_filename_from_url(_), do: "documento"

  @doc """
  Retorna ícone para tipo de documento.
  """
  @spec get_document_icon(String.t()) :: String.t()
  def get_document_icon(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> document_icon_for_extension()
  end

  def get_document_icon(_), do: "DOC"

  @doc """
  Retorna tipo amigável de documento.
  """
  @spec get_document_type(String.t()) :: String.t()
  def get_document_type(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> document_type_for_extension()
  end

  def get_document_type(_), do: "Documento"

  @doc """
  Valida tipos de documento permitidos.
  """
  @spec validate_document_type(String.t()) :: boolean()
  def validate_document_type(filename) when is_binary(filename) do
    App.Minio.supported_file_type?(filename)
  end

  def validate_document_type(_), do: false

  # ========================================
  # UTILITIES
  # ========================================

  @doc """
  Obtém status da mensagem.
  """
  @spec get_message_status(map()) :: String.t()
  def get_message_status(%{status: status}) when not is_nil(status), do: status
  def get_message_status(_), do: "sent"

  @doc """
  Conta respostas de uma mensagem.
  """
  @spec count_message_replies(integer(), list()) :: integer() | false
  def count_message_replies(message_id, messages) do
    reply_count = Enum.count(messages, fn msg ->
      case msg do
        %{is_system: true} -> false
        %{reply_to: reply_to} -> reply_to == message_id
        _ -> false
      end
    end)

    if reply_count > 0, do: reply_count, else: false
  end

  # ========================================
  # PRIVATE FUNCTIONS
  # ========================================

  # Pattern matching para ícones de documentos
  defp document_icon_for_extension(".pdf"), do: "PDF"
  defp document_icon_for_extension(".doc"), do: "DOC"
  defp document_icon_for_extension(".docx"), do: "DOC"
  defp document_icon_for_extension(".xls"), do: "XLS"
  defp document_icon_for_extension(".xlsx"), do: "XLS"
  defp document_icon_for_extension(".ppt"), do: "PPT"
  defp document_icon_for_extension(".pptx"), do: "PPT"
  defp document_icon_for_extension(_), do: "DOC"

  # Pattern matching para tipos de documentos
  defp document_type_for_extension(".pdf"), do: "PDF"
  defp document_type_for_extension(".doc"), do: "Word"
  defp document_type_for_extension(".docx"), do: "Word"
  defp document_type_for_extension(".xls"), do: "Excel"
  defp document_type_for_extension(".xlsx"), do: "Excel"
  defp document_type_for_extension(".ppt"), do: "PowerPoint"
  defp document_type_for_extension(".pptx"), do: "PowerPoint"
  defp document_type_for_extension(_), do: "Documento"
end
