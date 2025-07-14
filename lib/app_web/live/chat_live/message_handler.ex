defmodule AppWeb.ChatLive.MessageHandler do
  @moduledoc """
  Manipulador de mensagens para o chat em tempo real.

  Este módulo contém toda a lógica relacionada ao processamento, validação,
  criação e envio de mensagens extraída do AppWeb.ChatLive para melhorar
  a organização e eliminar anti-padrões.

  ## Funcionalidades
  - Criação e validação de mensagens
  - Processamento de anexos e link previews
  - Rate limiting e validações de segurança
  - Broadcast de mensagens em tempo real
  - Tratamento de respostas e threads
  - Formatação e determinação de tipos

  ## Anti-padrões Corrigidos
  - Long parameter list: Parâmetros agrupados em structs
  - Primitive obsession: Types definidos ao invés de strings
  - Complex extractions: with pipeline e pattern matching assertivo
  - Comments overuse: Logs focados e informativos
  - Non-assertive pattern matching: Pattern matching direto
  """

  require Logger
  alias App.Chat.RateLimiter
  alias Phoenix.PubSub
  use AppWeb, :live_view

  @type message_type :: :mensagem | :imagem | :documento | :audio | :system_notification
  @type message_status :: :sent | :delivered | :read | :system
  @type send_result :: {:noreply, Phoenix.LiveView.Socket.t()}
  @type validation_result :: :valid | {:error, String.t()}

  defmodule MessageRequest do
    @moduledoc """
    Estrutura para agrupar todos os parâmetros de uma requisição de mensagem.
    Elimina o anti-padrão Long parameter list.
    """

    @type t :: %__MODULE__{
      text: String.t(),
      socket: Phoenix.LiveView.Socket.t(),
      user_id: String.t(),
      attachments: AttachmentData.t(),
      link_preview: map() | nil,
      reply_to_id: integer() | nil
    }

    defstruct [:text, :socket, :user_id, :attachments, :link_preview, :reply_to_id]
  end

  defmodule AttachmentData do
    @moduledoc """
    Estrutura para dados de anexos de mensagem.
    Elimina primitive obsession agrupando dados relacionados.
    """

    @type t :: %__MODULE__{
      image_url: String.t() | nil,
      document_url: String.t() | nil,
      has_image: boolean(),
      has_document: boolean(),
      has_any: boolean()
    }

    defstruct [:image_url, :document_url, :has_image, :has_document, :has_any]

    def new(image_url, document_url) do
      has_image = not is_nil(image_url) and image_url != ""
      has_document = not is_nil(document_url) and document_url != ""

      %__MODULE__{
        image_url: image_url,
        document_url: document_url,
        has_image: has_image,
        has_document: has_document,
        has_any: has_image or has_document
      }
    end
  end

     defmodule MessageParams do
     @moduledoc """
     Estrutura para parâmetros de criação de mensagem.
     Normaliza construção de mensagens eliminando primitive obsession.
     """

     @type t :: %__MODULE__{
       text: String.t(),
       sender_id: String.t(),
       sender_name: String.t(),
       order_id: String.t(),
       tipo: AppWeb.ChatLive.MessageHandler.message_type(),
       status: AppWeb.ChatLive.MessageHandler.message_status(),
       reply_to: integer() | nil,
       is_reply: boolean(),
       image_url: String.t() | nil,
       document_url: String.t() | nil,
       document_name: String.t() | nil,
       link_preview_title: String.t() | nil,
       link_preview_description: String.t() | nil,
       link_preview_image: String.t() | nil,
       link_preview_url: String.t() | nil
     }

    defstruct [
      :text, :sender_id, :sender_name, :order_id, :tipo, :status,
      :reply_to, :is_reply, :image_url, :document_url, :document_name,
      :link_preview_title, :link_preview_description, :link_preview_image, :link_preview_url
    ]
  end

  # ========================================
  # MESSAGE SENDING - API Principal
  # ========================================

  @doc """
  Envia mensagem usando estrutura unificada.
  Elimina Long parameter list agrupando parâmetros relacionados.
  """
  @spec send_message(MessageRequest.t()) :: send_result()
  def send_message(%MessageRequest{} = request) do
    with :valid <- validate_message_request(request),
         {:ok, :allowed} <- check_rate_limit(request),
         {:ok, message} <- create_and_broadcast_message(request) do
      handle_successful_send(request.socket, message)
    else
      {:error, error_message} ->
        handle_send_error(request.socket, error_message)

      {:error, reason, wait_time} ->
        error_message = format_rate_limit_error(reason, wait_time)
        handle_send_error(request.socket, error_message)
    end
  end

  @doc """
  Constrói requisição de mensagem a partir de parâmetros do evento.
  Centraliza construção eliminando duplicação de código.
  """
  @spec build_message_request(String.t(), Phoenix.LiveView.Socket.t(), AttachmentData.t(), map() | nil) :: MessageRequest.t()
  def build_message_request(text, socket, attachments, link_preview) do
    %MessageRequest{
      text: String.trim(text),
      socket: socket,
      user_id: socket.assigns.current_user_id,
      attachments: attachments,
      link_preview: link_preview,
      reply_to_id: get_reply_to_id(socket)
    }
  end

  @doc """
  Processa mensagem legada mantendo compatibilidade.
  Usado para migração gradual do código existente.
  """
  @spec send_legacy_chat_message(Phoenix.LiveView.Socket.t(), String.t(), String.t() | nil) :: send_result()
  def send_legacy_chat_message(socket, text, image_url) do
    attachments = AttachmentData.new(image_url, nil)
    request = build_message_request(text, socket, attachments, nil)
    send_message(request)
  end

  # ========================================
  # MESSAGE VALIDATION
  # ========================================

  @doc """
  Valida requisição de mensagem usando pattern matching assertivo.
  Elimina Complex extractions in clauses.
  """
  @spec validate_message_request(MessageRequest.t()) :: validation_result()
  def validate_message_request(%MessageRequest{} = request) do
    with :valid <- validate_message_content(request) do
      validate_attachment_constraints(request)
    end
  end


  defp validate_message_content(%MessageRequest{text: text, attachments: attachments}) do
    text_empty = is_nil(text) or String.trim(text || "") == ""

    cond do
      text_empty and not attachments.has_any ->
        {:error, "Mensagem não pode estar vazia sem anexo"}

      not text_empty and String.length(text) > get_max_message_length() ->
        {:error, "Mensagem muito longa"}

      true ->
        :valid
    end
  end


  defp validate_attachment_constraints(%MessageRequest{attachments: attachments}) do
    if attachments.has_image and attachments.has_document do
      {:error, "Envie apenas um tipo de anexo por vez"}
    else
      :valid
    end
  end

  # ========================================
  # MESSAGE CREATION
  # ========================================

  @doc """
  Cria e faz broadcast da mensagem usando with pipeline.
  Elimina Complex extractions in clauses.
  """
  @spec create_and_broadcast_message(MessageRequest.t()) :: {:ok, map()} | {:error, String.t()}
  def create_and_broadcast_message(%MessageRequest{} = request) do
    with {:ok, message_params} <- build_message_params(request),
         {:ok, message} <- App.Chat.create_message(message_params) do
      broadcast_message(request.socket, message)
      {:ok, message}
    else
      {:error, changeset} when is_map(changeset) ->
        {:error, format_changeset_errors(changeset)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Constrói parâmetros de mensagem usando pattern matching assertivo.
  Elimina Primitive obsession com tipos bem definidos.
  """
  @spec build_message_params(MessageRequest.t()) :: {:ok, MessageParams.t()}
  def build_message_params(%MessageRequest{} = request) do
    message_type = determine_message_type(request)

    base_params = %MessageParams{
      text: request.text || "",
      sender_id: request.socket.assigns.current_user_id,
      sender_name: request.socket.assigns.current_user_name,
      order_id: request.socket.assigns.order_id,
      tipo: message_type,
      status: :sent,
      reply_to: request.reply_to_id,
      is_reply: not is_nil(request.reply_to_id)
    }

    enhanced_params = base_params
    |> add_image_params(request.attachments.image_url)
    |> add_document_params(request.attachments.document_url)
    |> add_link_preview_params(request.link_preview)

    {:ok, enhanced_params}
  end

  @doc """
  Determina tipo de mensagem usando pattern matching assertivo.
  Elimina Primitive obsession retornando átomos ao invés de strings.
  """
  @spec determine_message_type(MessageRequest.t()) :: message_type()
  def determine_message_type(%MessageRequest{attachments: attachments, text: text}) do
    cond do
      attachments.has_image -> :imagem
      attachments.has_document -> :documento
      not is_nil(text) and text != "" -> :mensagem
      true -> :mensagem
    end
  end

  # ========================================
  # MESSAGE ENHANCEMENT
  # ========================================


  defp add_image_params(%MessageParams{} = params, image_url) when is_binary(image_url) and image_url != "" do
    %{params | image_url: image_url}
  end
  defp add_image_params(params, _), do: params


  defp add_document_params(%MessageParams{} = params, document_url) when is_binary(document_url) and document_url != "" do
    %{params |
      document_url: document_url,
      document_name: extract_filename_from_url(document_url)
    }
  end
  defp add_document_params(params, _), do: params


  defp add_link_preview_params(%MessageParams{} = params, %{title: title, description: desc, image: image, url: url}) do
    %{params |
      link_preview_title: title,
      link_preview_description: desc,
      link_preview_image: image,
      link_preview_url: url
    }
  end
  defp add_link_preview_params(params, _), do: params

  # ========================================
  # MESSAGE BROADCASTING
  # ========================================

  @doc """
  Faz broadcast da mensagem usando PubSub.
  Centraliza lógica de broadcast.
  """
  @spec broadcast_message(Phoenix.LiveView.Socket.t(), map()) :: :ok
  def broadcast_message(socket, message) do
    topic = "order:#{socket.assigns.order_id}"
    PubSub.broadcast(App.PubSub, topic, {:new_message, message})
  end

  # ========================================
  # RESPONSE HANDLING
  # ========================================


  defp handle_successful_send(socket, _message) do
    {:noreply,
     socket
     |> assign(:message, "")
     |> assign(:replying_to, nil)
     |> assign(:message_error, nil)
     |> Phoenix.LiveView.put_flash(:info, "Mensagem enviada com sucesso!")}
  end


  defp handle_send_error(socket, error_message) do
    {:noreply,
     socket
     |> assign(:message_error, error_message)
     |> Phoenix.LiveView.put_flash(:error, "Erro ao enviar mensagem: #{error_message}")}
  end

  # ========================================
  # RATE LIMITING
  # ========================================


  defp check_rate_limit(%MessageRequest{user_id: user_id, text: text}) do
    case RateLimiter.check_message_rate(user_id, text) do
      {:ok, :allowed} -> {:ok, :allowed}
      error -> error
    end
  end


  def record_message_sent(%MessageRequest{user_id: user_id, text: text}) do
    RateLimiter.record_message(user_id, text)
  end

  # ========================================
  # UTILITY FUNCTIONS
  # ========================================


  defp get_reply_to_id(%{assigns: %{replying_to: %{id: id}}}), do: id
  defp get_reply_to_id(_), do: nil


  defp extract_filename_from_url(url) when is_binary(url) do
    url |> String.split("/") |> List.last() || "documento"
  end
  defp extract_filename_from_url(_), do: "documento"


  defp format_changeset_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} -> "#{field}: #{message}" end)
  end


  defp format_rate_limit_error(reason, wait_time) do
    case reason do
      :rate_limited -> "Muitas mensagens. Aguarde #{wait_time} segundos."
      :duplicate_spam -> "Não repita a mesma mensagem. Aguarde #{wait_time} segundos."
      :long_message_spam -> "Muitas mensagens longas. Aguarde #{wait_time} segundos."
      _ -> "Rate limit atingido. Aguarde #{wait_time} segundos."
    end
  end


  defp get_max_message_length do
    case Application.get_env(:app, :chat_config) do
      %{security_config: %{max_message_length: length}} -> length
      _ -> 1000
    end
  end

  # ========================================
  # LINK PREVIEW PROCESSING
  # ========================================

  @doc """
  Processa mensagem para detectar e extrair preview de links.
  Usa with pipeline para controle de fluxo assertivo.
  """
  @spec process_message_for_link_preview(String.t()) :: map() | nil
  def process_message_for_link_preview(message_text) when is_binary(message_text) do
    with {:ok, link_data} <- App.LinkPreview.process_message_for_links(message_text),
         true <- not is_nil(link_data) do
      link_data
    else
      _ -> nil
    end
  end

  def process_message_for_link_preview(_), do: nil

  # ========================================
  # MESSAGE TYPES CONVERSION
  # ========================================

  @doc """
  Converte tipo de mensagem de string para átomo.
  Elimina Primitive obsession mantendo compatibilidade.
  """
  @spec normalize_message_type(String.t() | atom()) :: message_type()
  def normalize_message_type(tipo) when is_atom(tipo), do: tipo
  def normalize_message_type("mensagem"), do: :mensagem
  def normalize_message_type("imagem"), do: :imagem
  def normalize_message_type("documento"), do: :documento
  def normalize_message_type("audio"), do: :audio
  def normalize_message_type("system_notification"), do: :system_notification
  def normalize_message_type(_), do: :mensagem

  @doc """
  Converte status de mensagem de string para átomo.
  Elimina Primitive obsession mantendo compatibilidade.
  """
  @spec normalize_message_status(String.t() | atom()) :: message_status()
  def normalize_message_status(status) when is_atom(status), do: status
  def normalize_message_status("sent"), do: :sent
  def normalize_message_status("delivered"), do: :delivered
  def normalize_message_status("read"), do: :read
  def normalize_message_status("system"), do: :system
  def normalize_message_status(_), do: :sent
end
