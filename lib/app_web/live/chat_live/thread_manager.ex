defmodule AppWeb.ChatLive.ThreadManager do
  @moduledoc """
  Gerenciador de threads e respostas para o chat em tempo real.

  Este módulo contém toda a lógica relacionada ao gerenciamento de threads,
  respostas e navegação entre mensagens extraída do AppWeb.ChatLive para
  melhorar a organização e eliminar anti-padrões.

  ## Funcionalidades
  - Gerenciamento de threads e respostas
  - Criação e envio de replies
  - Navegação entre mensagens relacionadas
  - Preview de mensagens originais
  - Estados de thread (aberto/fechado)
  - Formatação e contadores de replies

  ## Anti-padrões Corrigidos
  - Long parameter list: Parâmetros agrupados em structs especializados
  - Primitive obsession: Types definidos ao invés de strings simples
  - Complex extractions: with pipeline e pattern matching assertivo
  - Comments overuse: Logs limpos sem emojis desnecessários
  - Non-assertive pattern matching: Pattern matching direto
  """

  require Logger
  alias App.Chat
  alias Phoenix.PubSub
  use AppWeb, :live_view

  @type thread_action :: :show | :close | :reply | :cancel_reply
  @type thread_result :: {:ok, Phoenix.LiveView.Socket.t()} | {:error, String.t()}

  defmodule ThreadRequest do
    @moduledoc """
    Estrutura para requisições de thread.
    Elimina o anti-padrão Long parameter list.
    """

    @type t :: %__MODULE__{
      message_id: String.t() | integer(),
      socket: Phoenix.LiveView.Socket.t(),
      action: atom()
    }

    defstruct [:message_id, :socket, :action]
  end

  defmodule ReplyRequest do
    @moduledoc """
    Estrutura para requisições de resposta.
    Elimina primitive obsession normalizando dados de reply.
    """

    @type t :: %__MODULE__{
      text: String.t(),
      socket: Phoenix.LiveView.Socket.t(),
      root_message: map() | nil,
      user_id: String.t(),
      user_name: String.t(),
      order_id: String.t()
    }

    defstruct [:text, :socket, :root_message, :user_id, :user_name, :order_id]

    def new(text, socket) do
      %__MODULE__{
        text: String.trim(text),
        socket: socket,
        root_message: socket.assigns[:thread_root_message],
        user_id: socket.assigns.current_user_id,
        user_name: socket.assigns.current_user_name,
        order_id: socket.assigns.order_id
      }
    end
  end

  defmodule ThreadState do
    @moduledoc """
    Estrutura para estado de thread.
    Normaliza dados de thread eliminando primitive obsession.
    """

    @type t :: %__MODULE__{
      messages: [map()],
      root_message: map() | nil,
      replies: [map()],
      is_open: boolean(),
      reply_text: String.t()
    }

    defstruct messages: [], root_message: nil, replies: [], is_open: false, reply_text: ""

    def empty do
      %__MODULE__{}
    end

    def from_messages(thread_messages) when is_list(thread_messages) do
      {root_message, replies} = case thread_messages do
        [] -> {nil, []}
        [root | rest] -> {root, rest}
      end

      %__MODULE__{
        messages: thread_messages,
        root_message: root_message,
        replies: replies,
        is_open: true,
        reply_text: ""
      }
    end
  end

  defmodule MessagePreview do
    @moduledoc """
    Estrutura para preview de mensagem original.
    Elimina maps simples em favor de structs tipados.
    """

    @type t :: %__MODULE__{
      id: integer(),
      text: String.t(),
      sender_name: String.t(),
      full_text: String.t()
    }

    defstruct [:id, :text, :sender_name, :full_text]
  end

  # ========================================
  # THREAD MANAGEMENT - API Principal
  # ========================================

  @doc """
  Processa requisição de reply para mensagem usando estrutura unificada.
  Elimina Long parameter list agrupando parâmetros relacionados.
  """
  @spec handle_reply_to_message(ThreadRequest.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_reply_to_message(%ThreadRequest{} = request) do
    with {:ok, message} <- fetch_message(request.message_id),
         {:ok, updated_socket} <- setup_reply_context(request.socket, message) do
      {:noreply, updated_socket}
    else
      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(request.socket, :error, "Mensagem não encontrada")}
    end
  end

  @doc """
  Cancela reply ativo limpando estado.
  Normaliza ação usando pattern matching assertivo.
  """
  @spec handle_cancel_reply(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cancel_reply(socket) do
    {:noreply, Phoenix.LiveView.assign(socket, :replying_to, nil)}
  end

  @doc """
  Exibe thread de uma mensagem usando with pipeline.
  Elimina Complex extractions in clauses.
  """
  @spec handle_show_thread(ThreadRequest.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_show_thread(%ThreadRequest{} = request) do
    with {:ok, message_id} <- parse_message_id(request.message_id),
         thread_messages <- Chat.get_thread_messages(message_id),
         thread_state <- ThreadState.from_messages(thread_messages),
         {:ok, updated_socket} <- apply_thread_state(request.socket, thread_state) do
      {:noreply, updated_socket}
    else
      {:error, reason} ->
        Logger.warning("Failed to show thread: #{inspect(reason)}")
        {:noreply, request.socket}
    end
  end

  @doc """
  Fecha thread ativa limpando estado.
  Usa ThreadState.empty() para garantir limpeza completa.
  """
  @spec handle_close_thread(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close_thread(socket) do
    empty_state = ThreadState.empty()
    updated_socket = apply_empty_thread_state(socket, empty_state)
    {:noreply, updated_socket}
  end

  @doc """
  Atualiza texto de reply da thread usando pattern matching assertivo.
  Normaliza entrada eliminando primitive obsession.
  """
  @spec handle_update_thread_reply(String.t(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_thread_reply(reply_text, socket) when is_binary(reply_text) do
    {:noreply, Phoenix.LiveView.assign(socket, :thread_reply_text, reply_text)}
  end

  def handle_update_thread_reply(_invalid_text, socket) do
    {:noreply, socket}
  end

  @doc """
  Envia resposta de thread usando with pipeline robusto.
  Elimina Complex extractions in clauses com validação assertiva.
  """
  @spec handle_send_thread_reply(ReplyRequest.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_send_thread_reply(%ReplyRequest{} = request) do
    with :valid <- validate_reply_request(request),
         {:ok, message} <- create_reply_message(request),
         :ok <- broadcast_reply_message(request, message),
         {:ok, updated_socket} <- update_thread_state(request, message) do
      {:noreply, Phoenix.LiveView.put_flash(updated_socket, :info, "Resposta enviada!")}
    else
      {:error, :empty_text} ->
        {:noreply, Phoenix.LiveView.put_flash(request.socket, :error, "Resposta não pode estar vazia")}

      {:error, :no_thread} ->
        {:noreply, Phoenix.LiveView.put_flash(request.socket, :error, "Thread não encontrada")}

      {:error, :create_failed} ->
        {:noreply, Phoenix.LiveView.put_flash(request.socket, :error, "Erro ao enviar resposta")}

      {:error, reason} ->
        Logger.warning("Failed to send thread reply: #{inspect(reason)}")
        {:noreply, Phoenix.LiveView.put_flash(request.socket, :error, "Erro inesperado ao enviar resposta")}
    end
  end

  @doc """
  Salta para mensagem específica fechando threads.
  Elimina primitive obsession com types bem definidos.
  """
  @spec handle_jump_to_message(String.t(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_jump_to_message(message_id, socket) when is_binary(message_id) do
    with {:ok, parsed_id} <- parse_message_id(message_id),
         {:ok, _message} <- find_message_in_list(parsed_id, socket.assigns.messages) do
      {:noreply,
       socket
       |> Phoenix.LiveView.assign(:show_thread, false)
       |> Phoenix.LiveView.push_event("scroll-to-message", %{message_id: message_id})}
    else
      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :info, "Mensagem não está visível no chat")}
    end
  end

  # ========================================
  # MESSAGE PREVIEW & FORMATTING
  # ========================================

  @doc """
  Constrói preview de mensagem original usando pattern matching assertivo.
  Elimina Complex extractions in clauses.
  """
  @spec build_original_message_preview(integer(), [map()]) :: MessagePreview.t() | nil
  def build_original_message_preview(reply_to_id, messages) when is_integer(reply_to_id) and is_list(messages) do
    case find_message_by_id(reply_to_id, messages) do
      {:ok, original_message} ->
        preview_text = truncate_message_text(original_message.text, 80)

        %MessagePreview{
          id: original_message.id,
          text: preview_text,
          sender_name: original_message.sender_name,
          full_text: original_message.text
        }

      {:error, :not_found} ->
        nil
    end
  end

  def build_original_message_preview(_invalid_id, _messages), do: nil

  @doc """
  Formata contador de replies usando pattern matching assertivo.
  Elimina primitive obsession com types bem definidos.
  """
  @spec format_thread_reply_counter(integer() | false) :: String.t()
  def format_thread_reply_counter(reply_count) when is_integer(reply_count) and reply_count > 0 do
    case reply_count do
      1 -> "1 resposta"
      count when count > 1 -> "#{count} respostas"
    end
  end

  def format_thread_reply_counter(_), do: "Thread"

  @doc """
  Obtém cor de reply de thread usando pattern matching assertivo.
  Elimina primitive obsession normalizando cores.
  """
  @spec get_thread_reply_color(String.t(), String.t(), String.t()) :: String.t()
  def get_thread_reply_color(sender_id, current_user_id, _sender_name) when is_binary(sender_id) and is_binary(current_user_id) do
    if sender_id == current_user_id do
      "bg-gradient-to-br from-green-50 to-green-100 border-l-4 border-[#25D366]"
    else
      "bg-gray-50 border-l-4 border-gray-300"
    end
  end

  def get_thread_reply_color(_invalid_sender, _current_user, _name), do: "bg-gray-50 border-l-4 border-gray-300"

  @doc """
  Obtém ID de reply do socket usando pattern matching assertivo.
  Normaliza extração conforme anti-padrões do Elixir.
  """
  @spec get_reply_to_id(Phoenix.LiveView.Socket.t()) :: integer() | nil
  def get_reply_to_id(%Phoenix.LiveView.Socket{assigns: %{replying_to: %{id: id}}}) when is_integer(id), do: id
  def get_reply_to_id(_socket), do: nil

  # ========================================
  # PRIVATE FUNCTIONS
  # ========================================

  # Busca mensagem por ID
  defp fetch_message(message_id) when is_binary(message_id) do
    case parse_message_id(message_id) do
      {:ok, parsed_id} -> fetch_message(parsed_id)
      error -> error
    end
  end

  defp fetch_message(message_id) when is_integer(message_id) do
    try do
      message = Chat.get_message!(message_id)
      {:ok, message}
    rescue
      _error -> {:error, :not_found}
    end
  end

  defp fetch_message(_invalid_id), do: {:error, :invalid_id}

  # Setup do contexto de reply
  defp setup_reply_context(socket, message) do
    updated_socket =
      socket
      |> assign(:replying_to, message)
      |> Phoenix.LiveView.push_event("focus-message-input", %{})

    {:ok, updated_socket}
  end

  # Parse de message ID
  defp parse_message_id(message_id) when is_binary(message_id) do
    case Integer.parse(message_id) do
      {parsed_id, ""} when parsed_id > 0 -> {:ok, parsed_id}
      _invalid -> {:error, :invalid_format}
    end
  end

  defp parse_message_id(message_id) when is_integer(message_id) and message_id > 0, do: {:ok, message_id}
  defp parse_message_id(_invalid_id), do: {:error, :invalid_format}

  # Aplicação de estado de thread
  defp apply_thread_state(socket, %ThreadState{} = state) do
    updated_socket =
      socket
      |> assign(:thread_messages, state.messages)
      |> assign(:thread_root_message, state.root_message)
      |> assign(:thread_replies, state.replies)
      |> assign(:show_thread, state.is_open)
      |> assign(:thread_reply_text, state.reply_text)

    {:ok, updated_socket}
  end

  # Aplicação de estado vazio de thread
  defp apply_empty_thread_state(socket, %ThreadState{} = empty_state) do
    socket
    |> assign(:thread_messages, empty_state.messages)
    |> assign(:thread_root_message, empty_state.root_message)
    |> assign(:thread_replies, empty_state.replies)
    |> assign(:show_thread, empty_state.is_open)
    |> assign(:thread_reply_text, empty_state.reply_text)
  end

  # Validação de requisição de reply
  defp validate_reply_request(%ReplyRequest{text: text, root_message: root_message}) do
    cond do
      is_nil(root_message) -> {:error, :no_thread}
      text == "" -> {:error, :empty_text}
      true -> :valid
    end
  end

  # Criação de mensagem de reply
  defp create_reply_message(%ReplyRequest{} = request) do
    params = %{
      text: request.text,
      sender_id: request.user_id,
      sender_name: request.user_name,
      order_id: request.order_id,
      tipo: "mensagem",
      status: "sent",
      reply_to: request.root_message.id
    }

    case Chat.create_message(params) do
      {:ok, message} -> {:ok, message}
      {:error, _changeset} -> {:error, :create_failed}
    end
  end

  # Broadcast de mensagem de reply
  defp broadcast_reply_message(%ReplyRequest{} = request, message) do
    topic = "order:#{request.order_id}"

    try do
      PubSub.broadcast(App.PubSub, topic, {:new_message, message})
      Logger.debug("Thread reply broadcast successful for topic: #{topic}")
      :ok
    rescue
      error ->
        Logger.error("Failed to broadcast thread reply: #{inspect(error)}")
        {:error, :broadcast_failed}
    end
  end

  # Atualização de estado de thread após envio
  defp update_thread_state(%ReplyRequest{} = request, message) do
    updated_thread = request.socket.assigns.thread_messages ++ [message]

    {_root, replies} = case updated_thread do
      [root | rest] -> {root, rest}
      _ -> {nil, []}
    end

    updated_socket =
      request.socket
      |> assign(:thread_reply_text, "")
      |> assign(:thread_messages, updated_thread)
      |> assign(:thread_replies, replies)

    {:ok, updated_socket}
  end

  # Busca mensagem por ID na lista
  defp find_message_by_id(id, messages) when is_integer(id) and is_list(messages) do
    case Enum.find(messages, fn msg -> msg.id == id end) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  defp find_message_by_id(_invalid_id, _messages), do: {:error, :invalid_params}

  # Busca mensagem na lista de mensagens carregadas
  defp find_message_in_list(message_id, messages) when is_integer(message_id) and is_list(messages) do
    target_message = Enum.find(messages, fn msg ->
      msg.id == message_id
    end)

    case target_message do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  defp find_message_in_list(_invalid_id, _messages), do: {:error, :invalid_params}

  # Truncamento de texto de mensagem
  defp truncate_message_text(text, max_length) when is_binary(text) and is_integer(max_length) and max_length > 0 do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate_message_text(text, _max_length) when is_binary(text), do: text
  defp truncate_message_text(_invalid_text, _max_length), do: ""
end
