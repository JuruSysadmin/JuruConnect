defmodule AppWeb.ChatLive.Components do
  @moduledoc """
  Componentes visuais e funções de formatação para o chat em tempo real.

  Este módulo contém todas as funções relacionadas à apresentação visual,
  formatação de dados, renderização de componentes e styling extraídas
  do AppWeb.ChatLive para melhorar a organização e eliminar anti-padrões.

  ## Funcionalidades
  - Formatação de tempo, arquivo e erro
  - Renderização de mensagens com highlights e tags
  - Sistema de cores e styling responsivo
  - Componentes visuais reutilizáveis
  - Validação e ícones de documentos
  - Classes CSS dinâmicas

  ## Anti-padrões Corrigidos
  - Primitive obsession: Types definidos ao invés de strings simples
  - Complex extractions: Pattern matching assertivo
  - Comments overuse: Logs limpos sem emojis desnecessários
  - Non-assertive pattern matching: Pattern matching direto
  - Long parameter list: Estruturas organizadas por responsabilidade
  """

  require Logger
  import Phoenix.HTML

  @type color_scheme :: %{
    bg: String.t(),
    light: String.t(),
    avatar: String.t()
  }

  @type upload_error :: :too_large | :not_accepted | :too_many_files | :external_client_failure | atom()
  @type rate_limit_reason :: :rate_limited | :duplicate_spam | :long_message_spam | atom()
  @type file_size_unit :: :bytes | :kb | :mb

  defmodule TimeFormat do
    @moduledoc """
    Estrutura para formatação de tempo.
    Elimina primitive obsession com tipos bem definidos.
    """

    @type t :: %__MODULE__{
      hour: integer(),
      minute: integer(),
      formatted: String.t()
    }

    defstruct [:hour, :minute, :formatted]

    def from_datetime(%DateTime{hour: hour, minute: minute}) do
      formatted = "#{String.pad_leading("#{hour}", 2, "0")}:#{String.pad_leading("#{minute}", 2, "0")}"

      %__MODULE__{
        hour: hour,
        minute: minute,
        formatted: formatted
      }
    end

    def from_datetime(_invalid), do: %__MODULE__{hour: 0, minute: 0, formatted: "Hora não disponível"}
  end

  defmodule UserColorPalette do
    @moduledoc """
    Estrutura para paleta de cores de usuário.
    Elimina maps simples em favor de structs tipados.
    """

    @type t :: %__MODULE__{
      bg: String.t(),
      light: String.t(),
      avatar: String.t(),
      username: String.t()
    }

    defstruct [:bg, :light, :avatar, :username]
  end

  defmodule FileInfo do
    @moduledoc """
    Estrutura para informações de arquivo.
    Normaliza dados de arquivo eliminando primitive obsession.
    """

    @type t :: %__MODULE__{
      size: integer(),
      formatted_size: String.t(),
      icon: String.t(),
      type: String.t(),
      is_valid: boolean()
    }

    defstruct [:size, :formatted_size, :icon, :type, :is_valid]

    def new(filename, size) when is_binary(filename) and is_integer(size) do
      %__MODULE__{
        size: size,
        formatted_size: format_size_internal(size),
        icon: get_icon_for_file(filename),
        type: get_type_for_file(filename),
        is_valid: validate_file_type(filename)
      }
    end

    def new(_invalid_filename, _invalid_size), do: %__MODULE__{size: 0, formatted_size: "0B", icon: "📄", type: "unknown", is_valid: false}

    defp format_size_internal(size) when is_integer(size) and size >= 1_048_576, do: "#{Float.round(size / 1_048_576, 1)}MB"
    defp format_size_internal(size) when is_integer(size) and size >= 1_024, do: "#{Float.round(size / 1_024, 1)}KB"
    defp format_size_internal(size) when is_integer(size), do: "#{size}B"
    defp format_size_internal(_), do: "Tamanho desconhecido"

    defp get_icon_for_file(filename) when is_binary(filename) do
      filename
      |> Path.extname()
      |> String.downcase()
      |> icon_for_extension()
    end
    defp get_icon_for_file(_), do: "📄"

    defp get_type_for_file(filename) when is_binary(filename) do
      filename |> Path.extname() |> String.downcase() |> String.slice(1..-1//-1)
    end
    defp get_type_for_file(_), do: "unknown"

    defp validate_file_type(filename) when is_binary(filename) do
      App.Minio.supported_file_type?(filename)
    end
    defp validate_file_type(_), do: false

    # Pattern matching assertivo para ícones de documentos
    defp icon_for_extension(".pdf"), do: "PDF"
    defp icon_for_extension(".doc"), do: "DOC"
    defp icon_for_extension(".docx"), do: "DOC"
    defp icon_for_extension(".xls"), do: "XLS"
    defp icon_for_extension(".xlsx"), do: "XLS"
    defp icon_for_extension(".ppt"), do: "PPT"
    defp icon_for_extension(".pptx"), do: "PPT"
    defp icon_for_extension(_), do: "DOC"
  end

  # ========================================
  # TIME & DATE FORMATTING
  # ========================================

  @doc """
  Formata DateTime usando pattern matching assertivo.
  Elimina primitive obsession com struct TimeFormat.
  """
  @spec format_time(DateTime.t() | any()) :: String.t()
  def format_time(%DateTime{} = datetime) do
    time_format = TimeFormat.from_datetime(datetime)
    time_format.formatted
  end

  def format_time(_invalid_datetime) do
    time_format = TimeFormat.from_datetime(nil)
    time_format.formatted
  end

  # ========================================
  # USER INTERFACE FORMATTING
  # ========================================

  @doc """
  Formata lista de usuários digitando usando pattern matching assertivo.
  Elimina condicionais complexas com cases bem definidos.
  """
  @spec format_typing_users(MapSet.t()) :: String.t()
  def format_typing_users(typing_users) when is_struct(typing_users, MapSet) do
    user_list = MapSet.to_list(typing_users)
    format_user_list_by_count(user_list)
  end

  def format_typing_users(_invalid_typing_users), do: ""

  # Pattern matching assertivo para contagem de usuários
  defp format_user_list_by_count([]), do: ""
  defp format_user_list_by_count([single_user]), do: single_user
  defp format_user_list_by_count([first_user, second_user]), do: "#{first_user} e #{second_user}"
  defp format_user_list_by_count(user_list) when length(user_list) > 2, do: "#{length(user_list)} usuários"

  @doc """
  Conta replies de mensagem usando pattern matching assertivo.
  Elimina Complex extractions in clauses.
  """
  @spec count_message_replies(integer(), [map()]) :: integer() | false
  def count_message_replies(message_id, messages) when is_integer(message_id) and is_list(messages) do
    reply_count = Enum.count(messages, &is_reply_to_message?(&1, message_id))

    case reply_count do
      0 -> false
      count when count > 0 -> count
    end
  end

  def count_message_replies(_invalid_id, _messages), do: false

  # Pattern matching assertivo para validação de reply
  defp is_reply_to_message?(%{is_system: true}, _message_id), do: false
  defp is_reply_to_message?(%{reply_to: reply_to}, message_id) when reply_to == message_id, do: true
  defp is_reply_to_message?(_message, _message_id), do: false

  @doc """
  Trunca texto de mensagem usando pattern matching assertivo.
  Elimina condicionais aninhadas.
  """
  @spec truncate_message_text(String.t(), integer()) :: String.t()
  def truncate_message_text(text, max_length) when is_binary(text) and is_integer(max_length) and max_length > 0 do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  def truncate_message_text(text, _max_length) when is_binary(text), do: text
  def truncate_message_text(_invalid_text, _max_length), do: ""

  # ========================================
  # MESSAGE RENDERING
  # ========================================

  @doc """
  Renderiza mensagem com highlights de menções usando pattern matching assertivo.
  Elimina primitive obsession com HTML semântico.
  """
  @spec render_message_with_mention_highlights(String.t()) :: Phoenix.HTML.safe()
  def render_message_with_mention_highlights(text) when is_binary(text) do
    text
    |> highlight_mentions()
    |> raw()
  end

  def render_message_with_mention_highlights(_invalid_text), do: raw("")

  @doc """
  Renderiza mensagem com tags clicáveis usando pattern matching assertivo.
  Elimina Complex extractions com pipeline limpo.
  """
  @spec render_message_with_tags(map()) :: Phoenix.HTML.safe()
  def render_message_with_tags(%{text: text}) when is_binary(text) do
    text
    |> escape_html_safely()
    |> convert_tags_to_links()
    |> raw()
  end

  def render_message_with_tags(_invalid_message), do: raw("")

  # ========================================
  # COLOR SYSTEM
  # ========================================

  @doc """
  Obtém esquema de cores para usuário usando hash determinístico.
  Elimina primitive obsession com UserColorPalette struct.
  """
  @spec get_user_color(String.t(), String.t()) :: UserColorPalette.t()
  def get_user_color(user_id, user_name) when is_binary(user_id) and is_binary(user_name) do
    hash = generate_color_hash(user_id, user_name)
    color_scheme = select_color_scheme(hash)
    username_color = select_username_color(hash)

    %UserColorPalette{
      bg: color_scheme.bg,
      light: color_scheme.light,
      avatar: color_scheme.avatar,
      username: username_color
    }
  end

  def get_user_color(_invalid_id, _invalid_name) do
    %UserColorPalette{
      bg: "bg-gray-500",
      light: "bg-gray-100",
      avatar: "bg-gray-500",
      username: "text-gray-600"
    }
  end

  @doc """
  Obtém cor de mensagem baseada no remetente usando pattern matching assertivo.
  Elimina condicionais com cores WhatsApp autênticas.
  """
  @spec get_message_color(String.t(), String.t(), String.t()) :: String.t()
  def get_message_color(sender_id, current_user_id, _sender_name)
      when is_binary(sender_id) and is_binary(current_user_id) do
    if sender_id == current_user_id do
      "rounded-br-sm text-gray-800 bg-[#DCF8C6]"
    else
      "bg-white border border-gray-200 text-gray-900 rounded-bl-sm shadow-sm"
    end
  end

  def get_message_color(_invalid_sender, _current_user, _name), do: "bg-gray-100"

  @doc """
  Obtém cor de username usando hash determinístico.
  Elimina primitive obsession com pattern matching assertivo.
  """
  @spec get_username_color(String.t(), String.t()) :: String.t()
  def get_username_color(user_id, user_name) when is_binary(user_id) and is_binary(user_name) do
    hash = generate_username_hash(user_id, user_name)
    select_username_color(hash)
  end

  def get_username_color(_invalid_id, _invalid_name), do: "text-gray-600"

  @doc """
  Obtém classe CSS para indicador de conexão usando pattern matching assertivo.
  Elimina condicionais simples com types bem definidos.
  """
  @spec get_connection_text_class(boolean()) :: String.t()
  def get_connection_text_class(true), do: "text-green-600"
  def get_connection_text_class(false), do: "text-red-500"

  # ========================================
  # ERROR FORMATTING
  # ========================================

  @doc """
  Formata erros de rate limit usando pattern matching assertivo.
  Elimina condicionais aninhadas com types bem definidos.
  """
  @spec format_rate_limit_error(rate_limit_reason(), integer()) :: String.t()
  def format_rate_limit_error(reason, wait_time) when is_integer(wait_time) and wait_time > 0 do
    case reason do
      :rate_limited -> "Muitas mensagens. Aguarde #{wait_time} segundos."
      :duplicate_spam -> "Não repita a mesma mensagem. Aguarde #{wait_time} segundos."
      :long_message_spam -> "Muitas mensagens longas. Aguarde #{wait_time} segundos."
      _other -> "Rate limit atingido. Aguarde #{wait_time} segundos."
    end
  end

  def format_rate_limit_error(_reason, _wait_time), do: "Rate limit atingido. Tente novamente."

  @doc """
  Formata erros de upload usando pattern matching assertivo.
  Elimina Enum.map/2 |> Enum.join/2 em favor de Enum.map_join/3.
  """
  @spec format_upload_error([upload_error()]) :: String.t()
  def format_upload_error(errors) when is_list(errors) do
    error_messages = Enum.map_join(errors, ", ", &format_single_upload_error/1)

    case errors do
      [_single_error] -> error_messages
      _multiple_errors -> "Problemas: " <> error_messages
    end
  end

  def format_upload_error(_invalid_errors), do: "Erro de upload desconhecido"

  @doc """
  Formata erros de changeset usando pattern matching assertivo.
  Elimina Enum.map/2 |> Enum.join/2 em favor de Enum.map_join/3.
  """
  @spec format_errors([{atom(), {String.t(), keyword()}}]) :: String.t()
  def format_errors(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn {field, {message, _opts}} ->
      "#{field}: #{message}"
    end)
  end

  def format_errors(_invalid_errors), do: "Erro de validação"

  # ========================================
  # FILE HANDLING
  # ========================================

  @doc """
  Formata tamanho de arquivo usando pattern matching assertivo.
  Elimina condicionais aninhadas com guards bem definidos.
  """
  @spec format_file_size(integer()) :: String.t()
  def format_file_size(size) when is_integer(size) and size >= 1_048_576 do
    "#{Float.round(size / 1_048_576, 1)}MB"
  end

  def format_file_size(size) when is_integer(size) and size >= 1_024 do
    "#{Float.round(size / 1_024, 1)}KB"
  end

  def format_file_size(size) when is_integer(size), do: "#{size}B"

  def format_file_size(_invalid_size), do: "Tamanho desconhecido"

  @doc """
  Obtém ícone de documento usando pattern matching assertivo.
  Elimina primitive obsession com text ao invés de emojis.
  """
  @spec get_document_icon(String.t()) :: String.t()
  def get_document_icon(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> icon_for_extension()
  end

  def get_document_icon(_invalid_filename), do: "DOC"

  @doc """
  Valida tipo de documento usando pattern matching assertivo.
  Elimina condicionais com delegação para módulo especializado.
  """
  @spec validate_document_type(String.t()) :: boolean()
  def validate_document_type(filename) when is_binary(filename) do
    App.Minio.supported_file_type?(filename)
  end

  def validate_document_type(_invalid_filename), do: false

  # ========================================
  # PRIVATE FUNCTIONS
  # ========================================

  # Highlights de menções usando regex
  defp highlight_mentions(text) when is_binary(text) do
    Regex.replace(~r/@(\w+)/, text, fn _match, username ->
      ~s(<span class="bg-blue-100 text-blue-800 px-1 rounded font-medium">@#{username}</span>)
    end)
  end

  defp highlight_mentions(_invalid_text), do: ""

  # Escape seguro de HTML
  defp escape_html_safely(text) when is_binary(text) do
    case html_escape(text) do
      {:safe, content} -> content
      content -> content
    end
  end

  defp escape_html_safely(_invalid_text), do: ""

  # Conversão de tags para links
  defp convert_tags_to_links(safe_text) when is_binary(safe_text) do
    Regex.replace(~r/#([a-zA-Z0-9_]+)/, safe_text, fn _full_match, tag ->
      """
      <a href="#" phx-click="filter_by_tag" phx-value-tag="#{tag}" class="text-blue-600 font-semibold hover:underline">
        ##{tag}
      </a>
      """
    end)
  end

  defp convert_tags_to_links(_invalid_text), do: ""

  # Geração de hash para cores
  defp generate_color_hash(user_id, user_name) when is_binary(user_id) and is_binary(user_name) do
    :crypto.hash(:md5, "#{user_id}#{user_name}")
    |> :binary.bin_to_list()
    |> Enum.take(3)
    |> Enum.sum()
  end

  defp generate_color_hash(_invalid_id, _invalid_name), do: 0

  # Geração de hash para username
  defp generate_username_hash(user_id, user_name) when is_binary(user_id) and is_binary(user_name) do
    :crypto.hash(:md5, "#{user_id}#{user_name}")
    |> :binary.bin_to_list()
    |> Enum.take(2)
    |> Enum.sum()
  end

  defp generate_username_hash(_invalid_id, _invalid_name), do: 0

  # Seleção de esquema de cores
  defp select_color_scheme(hash) when is_integer(hash) do
    color_schemes = [
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

    color_index = rem(hash, length(color_schemes))
    Enum.at(color_schemes, color_index)
  end

  defp select_color_scheme(_invalid_hash) do
    %{bg: "bg-gray-500", light: "bg-gray-100", avatar: "bg-gray-500"}
  end

  # Seleção de cor de username
  defp select_username_color(hash) when is_integer(hash) do
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

  defp select_username_color(_invalid_hash), do: "text-gray-600"

  # Formatação de erro individual de upload
  defp format_single_upload_error(:too_large), do: "Arquivo muito grande (máximo 5MB)"
  defp format_single_upload_error(:not_accepted), do: "Tipo de arquivo não aceito (apenas JPG, PNG, GIF)"
  defp format_single_upload_error(:too_many_files), do: "Apenas uma imagem por vez"
  defp format_single_upload_error(:external_client_failure), do: "Falha no upload"
  defp format_single_upload_error(error), do: "Erro: #{inspect(error)}"

  # Pattern matching assertivo para ícones de documentos (texto ao invés de emojis)
  defp icon_for_extension(".pdf"), do: "PDF"
  defp icon_for_extension(".doc"), do: "DOC"
  defp icon_for_extension(".docx"), do: "DOC"
  defp icon_for_extension(".xls"), do: "XLS"
  defp icon_for_extension(".xlsx"), do: "XLS"
  defp icon_for_extension(".ppt"), do: "PPT"
  defp icon_for_extension(".pptx"), do: "PPT"
  defp icon_for_extension(_), do: "DOC"
end
