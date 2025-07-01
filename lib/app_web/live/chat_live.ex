defmodule AppWeb.ChatLive do
  @moduledoc """
  LiveView responsável pela interface de chat em tempo real do sistema JuruConnect.

  Este módulo implementa um sistema completo de chat associado a pedidos específicos,
  oferecendo funcionalidades como:

  ## Funcionalidades Principais
  - Mensagens em tempo real via WebSocket
  - Indicadores de presença de usuários online
  - Indicadores de digitação
  - Upload e compartilhamento de imagens
  - Busca em mensagens
  - Carregamento paginado de mensagens antigas
  - Rate limiting para prevenção de spam
  - Interface responsiva para desktop, tablet e mobile

  ## Estrutura do Layout
  - Sidebar com informações do pedido e usuários online
  - Área principal de mensagens com scroll automático
  - Formulário de envio com suporte a anexos
  - Headers e overlays adaptativos para diferentes telas

  ## Eventos Tratados
  - `send_message` - Envio de novas mensagens
  - `load_older_messages` - Carregamento de mensagens anteriores
  - `typing_start/stop` - Controle de indicadores de digitação
  - `toggle_sidebar` - Controle da sidebar em dispositivos móveis
  - `search_messages` - Busca em mensagens existentes
  - Upload de imagens via drag-and-drop ou seleção

  ## Assigns do Socket
  - `:current_user` - Nome do usuário logado obtido via Guardian
  - `:order_id` - ID do pedido associado ao chat
  - `:messages` - Lista de mensagens carregadas
  - `:users_online` - Lista de usuários atualmente conectados
  - `:connected` - Status da conexão WebSocket
  - `:sidebar_open` - Estado da sidebar em dispositivos móveis

  O módulo utiliza Phoenix PubSub para comunicação em tempo real e Presence
  para rastreamento de usuários online.
  """
  use AppWeb, :live_view
  alias App.ChatConfig
  alias App.Chat.{MessageStatus, Notifications, RateLimiter}
  alias AppWeb.Presence
  alias Phoenix.PubSub

  @type message_status :: :sent | :delivered | :read | :system
  @type message_type :: :mensagem | :imagem | :documento | :audio | :system_notification
  @type notification_type :: :join | :leave

  @status_strings_to_atoms %{
    "sent" => :sent,
    "delivered" => :delivered,
    "read" => :read,
    "system" => :system
  }

  @type message_params :: %{
    text: String.t(),
    sender_id: String.t(),
    sender_name: String.t(),
    order_id: String.t(),
    tipo: message_type(),
    status: message_status(),
    reply_to: integer() | nil,
    is_reply: boolean(),
    image_url: String.t() | nil,
    document_url: String.t() | nil,
    audio_url: String.t() | nil,
    link_preview_title: String.t() | nil,
    link_preview_description: String.t() | nil,
    link_preview_image: String.t() | nil,
    link_preview_url: String.t() | nil
  }

  @impl true
  def mount(%{"order_id" => order_id} = _params, session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, socket |> put_flash(:error, "Usuário não autenticado") |> push_navigate(to: "/auth/login")}

      user ->
        initialized_socket =
          socket
          |> initialize_chat_socket(order_id)
          |> assign(:active_tag_filter, nil)

        if length(initialized_socket.assigns.messages) == 0 and not connected?(socket) do
          Process.send_after(self(), :reload_historical_messages, 1000)
        end

        {:ok, initialized_socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    attachment_data = %{
      image_url: process_image_upload(socket),
      document_url: process_document_upload(socket)
    }

    trimmed_text = String.trim(text)
    user_id = socket.assigns.current_user_id

    link_preview_data = if trimmed_text != "", do: process_message_for_link_preview(trimmed_text), else: nil

    validate_and_send_enhanced_message(
      %{text: trimmed_text, user_id: user_id, socket: socket},
      attachment_data,
      link_preview_data
    )
  end

  @impl true
  def handle_event("load_older_messages", _params, socket) do
    if socket.assigns.loading_messages do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:loading_messages, true)
       |> load_older_messages_async()}
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :message_error, nil)}
  end

  @impl true
  def handle_event("reload_messages", _params, socket) do
    send(self(), :reload_historical_messages)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    if String.trim(message) == "" and socket.assigns[:is_typing] do
      user_name = socket.assigns.current_user_name
      topic = socket.assigns.topic
      Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_stop, user_name})

      {:noreply, socket |> assign(:message, message) |> assign(:is_typing, false)}
    else
      {:noreply, assign(socket, :message, message)}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    updated_socket = cancel_upload_by_ref(socket, ref)
    {:noreply, updated_socket}
  end

  def handle_event("validate_image", _params, socket) do
    case socket.assigns.uploads.image.entries do
      [] ->
        {:noreply, socket}

      [entry | _] ->
        validate_image_entry(entry, socket)
    end
  end

  @impl true
  def handle_event("validate_document", _params, socket) do
    case socket.assigns.uploads.document.entries do
      [] ->
        {:noreply, socket}

      [entry | _] ->
        validate_document_entry(entry, socket)
    end
  end

  @impl true
  def handle_event("show_image", %{"url" => url}, socket) do
    {:noreply, assign(socket, :modal_image_url, url)}
  end

  @impl true
  def handle_event("close_image_modal", _params, socket) do
    {:noreply, assign(socket, :modal_image_url, nil)}
  end

  @impl true
  def handle_event("typing_start", _params, socket) do
    user_name = socket.assigns.current_user_name
    topic = socket.assigns.topic

    PubSub.broadcast(App.PubSub, topic, {:typing_start, user_name})
    Process.send_after(self(), :typing_timeout, ChatConfig.typing_timeout())

    {:noreply, assign(socket, :is_typing, true)}
  end

  @impl true
  def handle_event("typing_stop", _params, socket) do
    user_name = socket.assigns.current_user_name
    topic = socket.assigns.topic

    Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_stop, user_name})

    {:noreply, assign(socket, :is_typing, false)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    sidebar_open = not socket.assigns[:sidebar_open]

    {:noreply,
     socket
     |> assign(:sidebar_open, sidebar_open)
     |> push_event("toggle-sidebar", %{open: sidebar_open})}
  end

  @impl true
  def handle_event("toggle_search", _params, socket) do
    search_open = not socket.assigns[:search_open]
    {:noreply, assign(socket, :search_open, search_open)}
  end

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    settings_open = not socket.assigns[:settings_open]
    {:noreply, assign(socket, :settings_open, settings_open)}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    trimmed_query = String.trim(query)

    if String.length(trimmed_query) >= 2 do
      all_messages = get_all_messages_with_notifications(socket.assigns.messages, socket.assigns.system_notifications)

      filtered_messages = Enum.filter(all_messages, fn msg ->
        String.contains?(String.downcase(msg.text), String.downcase(trimmed_query))
      end)

      {:noreply, assign(socket, :filtered_messages, filtered_messages)}
    else
      all_messages = get_all_messages_with_notifications(socket.assigns.messages, socket.assigns.system_notifications)
      {:noreply, assign(socket, :filtered_messages, all_messages)}
    end
  end

  @impl true
  def handle_event("mark_message_read", %{"message_id" => message_id}, socket) do
    user_id = socket.assigns.current_user
    MessageStatus.mark_read(message_id, user_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    user_id = socket.assigns.current_user
    order_id = socket.assigns.order_id

    case List.last(socket.assigns.messages) do
      nil -> {:noreply, socket}
      last_message ->
        MessageStatus.mark_all_read_until(last_message.id, user_id, order_id)
        Notifications.mark_notifications_read(user_id, order_id)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_notification_settings", %{"settings" => settings}, socket) do
    user_id = socket.assigns.current_user_id

    parsed_settings = %{
      desktop_enabled: settings["desktop_enabled"] || true,
      email_enabled: settings["email_enabled"] || true,
      push_enabled: settings["push_enabled"] || true,
      sound_enabled: settings["sound_enabled"] || true
    }

    Notifications.update_user_settings(user_id, parsed_settings)
    {:noreply, put_flash(socket, :info, "Configurações de notificação atualizadas")}
  end

  @impl true
  def handle_event("mark_messages_read", _params, socket) do
    user_id = socket.assigns.current_user_id
    order_id = socket.assigns.order_id

    App.Chat.mark_all_messages_read(order_id, user_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("bulk_mark_read", _params, socket) do
    user_id = socket.assigns.current_user_id
    order_id = socket.assigns.order_id

    case App.Chat.bulk_mark_messages_read(order_id, user_id) do
      {:ok, count} when count > 0 ->
        PubSub.broadcast(App.PubSub, "order:#{order_id}",
          {:bulk_read_update, user_id, count})

        PubSub.broadcast(App.PubSub, "order:#{order_id}",
          {:bulk_read_notification, %{
            count: count,
            reader_id: user_id,
            order_id: order_id
          }})

        {:noreply, push_event(socket, "bulk-read-success", %{count: count})}

      {:ok, 0} ->
        {:noreply, put_flash(socket, :info, "Não há mensagens para marcar como lidas")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao marcar mensagens como lidas")}
    end
  end

  @impl true
  def handle_event("reply_to_message", %{"message_id" => message_id}, socket) do
    try do
      message = App.Chat.get_message!(message_id)
      {:noreply,
       socket
       |> assign(:replying_to, message)
       |> push_event("focus-message-input", %{})}
    rescue
      _ ->
        {:noreply, put_flash(socket, :error, "Mensagem não encontrada")}
    end
  end

  @impl true
  def handle_event("cancel_reply", _params, socket) do
    {:noreply, assign(socket, :replying_to, nil)}
  end

  @impl true
  def handle_event("show_thread", %{"message_id" => message_id}, socket) do
    thread_messages = App.Chat.get_thread_messages(message_id)

    {root_message, replies} = case thread_messages do
      [] -> {nil, []}
      [root | rest] -> {root, rest}
    end

    {:noreply,
     socket
     |> assign(:thread_messages, thread_messages)
     |> assign(:thread_root_message, root_message)
     |> assign(:thread_replies, replies)
     |> assign(:show_thread, true)
     |> assign(:thread_reply_text, "")}
  end

  @impl true
  def handle_event("close_thread", _params, socket) do
    {:noreply,
     socket
     |> assign(:thread_messages, [])
     |> assign(:thread_root_message, nil)
     |> assign(:thread_replies, [])
     |> assign(:show_thread, false)
     |> assign(:thread_reply_text, "")}
  end

  @impl true
  def handle_event("update_thread_reply", %{"reply" => text}, socket) do
    {:noreply, assign(socket, :thread_reply_text, text)}
  end

  @impl true
  def handle_event("audio_recording_started", _params, socket) do
    {:noreply, assign(socket, :is_recording_audio, true)}
  end

  @impl true
  def handle_event("audio_recording_error", %{"error" => error_message}, socket) do
    {:noreply,
     socket
     |> assign(:is_recording_audio, false)
     |> put_flash(:error, "Erro ao gravar áudio: #{error_message}")}
  end

  @impl true
  def handle_event("audio_recorded", audio_params, socket) do
    case process_recorded_audio(socket, audio_params) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}
      {:error, error_message} ->
        {:noreply, put_flash(socket, :error, "Erro ao processar áudio: #{error_message}")}
    end
  end

  @impl true
  def handle_event("start_audio_recording", _params, socket) do
    {:noreply,
     socket
     |> assign(:is_recording_audio, true)
     |> push_event("start_audio_recording", %{})}
  end

  @impl true
  def handle_event("stop_audio_recording", _params, socket) do
    {:noreply,
     socket
     |> assign(:is_recording_audio, false)
     |> push_event("stop_audio_recording", %{})}
  end

  @impl true
  def handle_event("play_audio_message", %{"audio_url" => audio_url}, socket) do
    {:noreply, push_event(socket, "play_audio_message", %{audio_url: audio_url})}
  end

  @impl true
  def handle_event("send_thread_reply", %{"reply" => text}, socket) do
    trimmed_text = String.trim(text)

    case socket.assigns[:thread_root_message] do
      nil ->
        {:noreply, put_flash(socket, :error, "Thread não encontrada")}

      root_message ->
        if trimmed_text == "" do
          {:noreply, put_flash(socket, :error, "Resposta não pode estar vazia")}
        else
          # Criar resposta na thread
          params = %{
            text: trimmed_text,
            sender_id: socket.assigns.current_user_id,
            sender_name: socket.assigns.current_user_name,
            order_id: socket.assigns.order_id,
            tipo: "mensagem",
            status: "sent",
            reply_to: root_message.id
          }

          case App.Chat.create_message(params) do
            {:ok, message} ->
              # Publicar a mensagem via PubSub
              topic = "order:#{socket.assigns.order_id}"
              PubSub.broadcast(App.PubSub, topic, {:new_message, message})

              # Atualizar thread local
              updated_thread = socket.assigns.thread_messages ++ [message]
              {_root, replies} = case updated_thread do
                [root | rest] -> {root, rest}
                _ -> {nil, []}
              end

              {:noreply,
               socket
               |> assign(:thread_reply_text, "")
               |> assign(:thread_messages, updated_thread)
               |> assign(:thread_replies, replies)
               |> put_flash(:info, "Resposta enviada!")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Erro ao enviar resposta")}
          end
        end
    end
  end

  @impl true
  def handle_event("jump_to_message", %{"message_id" => message_id}, socket) do
    # Encontrar a mensagem nas mensagens carregadas
    target_message = Enum.find(socket.assigns.messages, fn msg ->
      msg.id == String.to_integer(message_id)
    end)

    case target_message do
      nil ->
        {:noreply, put_flash(socket, :info, "Mensagem não está visível no chat")}
      _ ->
        {:noreply,
         socket
         |> assign(:show_thread, false)
         |> push_event("scroll-to-message", %{message_id: message_id})}
    end
  end

  @impl true
  def handle_info({:new_message, msg}, socket) do
    require Logger

    Logger.info("NOVA MENSAGEM RECEBIDA via PubSub:")
    Logger.info("  ID: #{msg.id}")
    Logger.info("  Texto: #{inspect(msg.text)}")
    Logger.info("  Tipo: #{msg.tipo}")
    Logger.info("  Image URL: #{inspect(msg.image_url)}")
    Logger.info("  Document URL: #{inspect(Map.get(msg, :document_url))}")
    Logger.info("  Sender: #{msg.sender_name} (#{msg.sender_id})")
    Logger.info("  Order ID: #{msg.order_id}")
    Logger.info("  Current User: #{socket.assigns.current_user_id}")
    Logger.info("  É própria mensagem?: #{msg.sender_id == socket.assigns.current_user_id}")

    case {msg.order_id, socket.assigns.order_id} do
      {same_order, same_order} ->
        Logger.info("MENSAGEM ACEITA - mesmo order_id")

        new_messages = socket.assigns.messages ++ [msg]
        user_id = socket.assigns.current_user_id

        Logger.info("Total mensagens após adicionar: #{length(new_messages)}")
        Logger.info("has_image? #{inspect(has_image?(msg))}")

        if msg.sender_id != user_id do
          App.Chat.mark_message_delivered(msg.id, user_id)
          Notifications.notify_new_message(user_id, msg, msg.order_id)
        end

        MessageStatus.update_user_presence(user_id, msg.order_id)

        all_messages = get_all_messages_with_notifications(new_messages, socket.assigns.system_notifications)

        {:noreply,
         socket
         |> assign(:messages, new_messages)
         |> assign(:filtered_messages, all_messages)
         |> push_event("scroll-to-bottom", %{})
         |> push_event("play-notification-sound", %{})
         |> push_event("mark-messages-as-read", %{order_id: msg.order_id})}

      {_different_order, _current_order} ->
        Logger.debug("MENSAGEM IGNORADA - order_id diferente")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:older_messages_loaded, older_messages, has_more}, socket) do
    new_messages = older_messages ++ socket.assigns.messages

    # ATUALIZAÇÃO: Usar função helper para mesclar mensagens + notificações
    all_messages = get_all_messages_with_notifications(new_messages, socket.assigns.system_notifications)

    {:noreply,
     socket
     |> assign(:messages, new_messages)
     |> assign(:filtered_messages, all_messages)
     |> assign(:has_more_messages, has_more)
     |> assign(:loading_messages, false)}
  end

  @impl true
  def handle_info(:reload_historical_messages, socket) do
    # CORREÇÃO: Força recarregamento das mensagens históricas
    order_id = socket.assigns.order_id

    {:ok, messages, has_more} = App.Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit())

    require Logger
    Logger.info("ChatLive - Historical reload: #{length(messages)} messages for order #{order_id}")

    # Mesclar com notificações existentes
    all_messages = get_all_messages_with_notifications(messages, socket.assigns.system_notifications)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:filtered_messages, all_messages)
     |> assign(:has_more_messages, has_more)}
  end

  @impl true
    def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    diff_start = System.monotonic_time(:microsecond)

    try do
      spawn(fn ->
        process_presence_notifications(diff, socket.assigns.topic, socket.assigns.current_user_id)
      end)

      presences = Presence.list(socket.assigns.topic)
      users_online = extract_unique_users_from_presences(presences)

      diff_end = System.monotonic_time(:microsecond)
      duration_ms = (diff_end - diff_start) / 1000

      require Logger
      Logger.debug("Presence diff handled in #{Float.round(duration_ms, 2)}ms")

      {:noreply,
       socket
       |> assign(:presences, presences)
       |> assign(:users_online, users_online)}
    rescue
      error ->
        require Logger
        Logger.error("Error processing presence diff: #{inspect(error)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:system_notification, notification}, socket) do
    # Não mostrar notificação de sistema para o próprio usuário que a gerou
    if notification.target_user_id == socket.assigns.current_user_id do
      {:noreply, socket}
    else
      require Logger
      Logger.debug("Recebida notificação do sistema: #{notification.text}")

      # CORREÇÃO: Adicionar notificação APENAS ao assign temporário
      # Não misturar com mensagens persistentes
      system_notifications = socket.assigns.system_notifications ++ [notification]

      # Limpar notificações antigas (mais de 5 minutos)
      cutoff_time = DateTime.add(DateTime.utc_now(), -300, :second)
      fresh_notifications = Enum.filter(system_notifications, fn notif ->
        DateTime.compare(notif.inserted_at, cutoff_time) == :gt
      end)

      {:noreply,
       socket
       |> assign(:system_notifications, fresh_notifications)
       |> push_event("scroll-to-bottom", %{})}
    end
  end

  @impl true
  def handle_info({:typing_start, user_name}, socket) do
    if user_name != socket.assigns.current_user_name do
      typing_users = MapSet.put(socket.assigns.typing_users, user_name)
      {:noreply, assign(socket, :typing_users, typing_users)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:typing_stop, user_name}, socket) do
    typing_users = MapSet.delete(socket.assigns.typing_users, user_name)
    {:noreply, assign(socket, :typing_users, typing_users)}
  end

  @impl true
  def handle_info(:typing_timeout, socket) do
    if socket.assigns[:is_typing] do
      user_name = socket.assigns.current_user_name
      topic = socket.assigns.topic

      Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_stop, user_name})
    end

    {:noreply, assign(socket, :is_typing, false)}
  end

  @impl true
  def handle_info({:message_status_update, message_id, status, user_id}, socket) do
    # Atualizar o status da mensagem na lista local
    updated_messages = Enum.map(socket.assigns.messages, fn msg ->
      if msg.id == message_id do
        case status do
          :delivered ->
            delivered_to = msg.delivered_to || []
            %{msg | delivered_to: [user_id | delivered_to], status: "delivered"}
          :read ->
            read_by = msg.read_by || []
            %{msg | read_by: [user_id | read_by], status: "read"}
        end
      else
        msg
      end
    end)

    {:noreply,
     socket
     |> assign(:messages, updated_messages)
     |> assign(:filtered_messages, updated_messages)}
  end

  @impl true
  def handle_info({:desktop_notification, notification_data}, socket) do
    # Enviar notificação desktop via JavaScript
    {:noreply, push_event(socket, "desktop-notification", notification_data)}
  end

  @impl true
  def handle_info({:status_update, message_id, user_id, status}, socket) do
    # Atualizar status de mensagem na interface
    {:noreply, push_event(socket, "message-status-update", %{
      message_id: message_id,
      user_id: user_id,
      status: status
    })}
  end

  @impl true
  def handle_info({:bulk_read_update, user_id, count}, socket) do
    # Atualizar contador de mensagens lidas
    {:noreply, push_event(socket, "bulk-read-update", %{
      user_id: user_id,
      count: count
    })}
  end

  @impl true
  def handle_info({:message_read_notification, %{message_id: message_id, reader_id: reader_id}}, socket) do
    # Notificar que uma mensagem foi lida por outro usuário
    if socket.assigns.current_user_id != reader_id do
      Notifications.notify_message_read(socket.assigns.current_user_id, message_id, reader_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:bulk_read_notification, %{count: count, reader_id: reader_id, order_id: order_id}}, socket) do
    # Notificar sobre bulk read
    if socket.assigns.current_user_id != reader_id and socket.assigns.order_id == order_id do
      App.Chat.Notifications.notify_bulk_read(socket.assigns.current_user_id, order_id, count, reader_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:mention_notification, %{message_id: message_id, mentioned_user: username} = notification}, socket) do
    # Verificar se o usuário mencionado é o usuário atual
    if socket.assigns.current_user_name == username do
      # Adicionar notificação visual
      {:noreply,
       socket
       |> put_flash(:info, "Você foi mencionado por #{notification.sender_name}")
       |> push_event("mention-notification", %{
         message_id: message_id,
         sender_name: notification.sender_name,
         text: notification.text
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_by_tag", %{"tag" => tag}, socket) do
    filtered_messages = App.Chat.list_messages_by_tag(socket.assigns.order_id, tag)

    {:noreply,
      socket
      |> assign(:filtered_messages, filtered_messages)
      |> assign(:active_tag_filter, tag)
      |> assign(:has_more_messages, false) # Desativa "carregar mais" na visão de filtro
    }
  end

  @impl true
  def handle_event("clear_tag_filter", _params, socket) do
    {:noreply,
      socket
      |> assign(:filtered_messages, socket.assigns.messages)
      |> assign(:active_tag_filter, nil)
      |> assign(:has_more_messages, true) # Reativar se necessário
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="chat-container"
      class="h-screen w-screen bg-gray-50 font-sans antialiased flex flex-col lg:flex-row overflow-hidden fixed inset-0"
      phx-hook="ChatHook"
      role="main"
    >
      <div id="audio-recorder" phx-hook="AudioRecorderHook" style="display: none;"></div>
      <!-- Mobile/Tablet Header -->
      <div class="lg:hidden bg-white border-b border-gray-200 p-4 flex items-center justify-between shadow-sm">
        <button
          id="toggle-sidebar"
          class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors text-sm font-medium"
          phx-click="toggle_sidebar"
          aria-label="Toggle sidebar"
        >
          Menu
        </button>
        <div class="flex-1 text-center">
          <h1 class="text-base font-bold text-gray-900 truncate">Pedido #{@order["orderId"]}</h1>
          <p class="text-xs text-gray-600">{@order["status"]}</p>
        </div>
        <div class="flex items-center space-x-2">
          <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
          <button
            class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors text-xs font-medium"
            aria-label="Buscar mensagens"
            title="Buscar"
          >
            Buscar
          </button>
        </div>
      </div>

            <!-- Sidebar -->
      <aside
        id="sidebar"
        class={"w-full md:w-80 lg:w-96 xl:w-[400px] bg-white border-r border-gray-200 flex flex-col shadow-xl z-30 flex-shrink-0
               #{if @sidebar_open, do: "flex", else: "hidden"} lg:flex absolute lg:relative inset-y-0 left-0 transform #{if @sidebar_open, do: "translate-x-0", else: "-translate-x-full"} lg:translate-x-0 transition-transform duration-300 ease-in-out"}
        role="complementary"
        aria-label="Informações do pedido e usuários online"
      >

    <!-- Close button for mobile/tablet -->
        <div class="lg:hidden p-4 border-b border-gray-100 flex items-center justify-between">
          <h2 class="text-lg font-bold text-gray-900">Informações</h2>
          <button
            phx-click="toggle_sidebar"
            class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors text-sm font-medium"
            aria-label="Fechar sidebar"
          >
            Fechar
          </button>
        </div>

        <!-- Header com logo/nome -->
        <header class="px-6 py-4 border-b border-gray-100 bg-gradient-to-r from-blue-50 via-indigo-50 to-purple-50">
          <div class="flex items-center space-x-2 md:space-x-3">
            <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-purple-600 rounded-lg flex items-center justify-center shadow-md">
              <span class="text-white text-sm font-bold">JC</span>
            </div>
            <div>
              <h1 class="text-base md:text-lg font-bold text-gray-900 tracking-tight">JuruConnect</h1>
              <p class="text-xs text-gray-600 font-medium">Chat por Pedido</p>
            </div>
          </div>
        </header>

    <!-- Pedido Info Card -->
        <section class="px-6 py-4" aria-labelledby="order-info-title">
          <h2 id="order-info-title" class="sr-only">Informações do Pedido</h2>
          <div class="bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 rounded-xl p-3 md:p-4 border border-blue-100 shadow-sm hover:shadow-md transition-shadow duration-300">
            <div class="flex items-center justify-between mb-3 flex-wrap gap-2">
              <div class="flex items-center space-x-2">
                <h3 class="text-sm md:text-base font-bold text-gray-900">
                  Pedido #{@order["orderId"]}
                </h3>
              </div>
              <span class={get_status_class(@order["status"])}>
                {@order["status"]}
              </span>
            </div>

            <dl class="space-y-3 text-sm lg:text-base">
              <div class="flex justify-between items-center">
                <dt class="text-gray-600 font-medium">
                  Cliente:
                </dt>
                <dd
                  class="font-semibold text-gray-900 truncate ml-2 max-w-28 md:max-w-32"
                  title={@order["customerName"]}
                >
                  {@order["customerName"]}
                </dd>
              </div>
              <div class="flex justify-between items-center">
                <dt class="text-gray-600 font-medium">
                  Valor:
                </dt>
                <dd class="font-bold text-green-700 text-sm md:text-base">
                  R$ {format_currency(@order["amount"])}
                </dd>
              </div>
              <div class="flex justify-between items-center">
                <dt class="text-gray-600 font-medium">
                  Entrega:
                </dt>
                <dd class="font-semibold text-gray-900">{@order["deliveryType"]}</dd>
              </div>
              <div class="flex justify-between items-center">
                <dt class="text-gray-600 font-medium">
                  Data:
                </dt>
                <dd class="font-semibold text-gray-900">{format_date(@order["deliveryDate"])}</dd>
              </div>
            </dl>
          </div>
        </section>

    <!-- Usuários Online -->
        <section class="px-6 py-4 flex-1" aria-labelledby="users-online-title">
          <h2 id="users-online-title" class="text-sm lg:text-base font-bold text-gray-800 mb-3 lg:mb-4 flex items-center">
            <div
              class="w-2 h-2 bg-green-500 rounded-full mr-2 animate-pulse shadow-sm"
              aria-hidden="true"
            >
            </div>
            Online ({length(@users_online)})
          </h2>

          <div class="space-y-2 max-h-60 lg:max-h-80 overflow-y-auto" role="list">
            <%= if Enum.empty?(@users_online) do %>
              <div class="text-center py-8">
                <p class="text-sm text-gray-500 italic">Nenhum usuário online</p>
              </div>
            <% else %>
              <%= for user <- @users_online do %>
                <div
                  class="flex items-center p-2 md:p-3 rounded-lg md:rounded-xl hover:bg-gray-50 transition-all duration-200 border border-transparent hover:border-gray-200 hover:shadow-sm group"
                  role="listitem"
                >
                  <div
                    class={"w-8 h-8 md:w-10 md:h-10 rounded-full flex items-center justify-center mr-2 md:mr-3 shadow-md group-hover:shadow-lg transition-shadow duration-200 " <> get_avatar_color(user, user)}
                    aria-hidden="true"
                  >
                    <span class="text-white text-xs md:text-sm font-bold">{get_user_initial(user)}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <span class="text-xs md:text-sm font-semibold text-gray-800 truncate block">{user}</span>
                    <%= if user == @current_user_name do %>
                      <span class="text-xs text-blue-600 font-medium">(Você)</span>
                    <% end %>
                  </div>
                  <div
                    class="w-2 h-2 bg-green-400 rounded-full flex-shrink-0 animate-pulse"
                    aria-label="Online"
                    title="Online"
                  >
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>

    <!-- Footer com informações do usuário atual -->
        <footer class="px-6 py-4 border-t border-gray-100 bg-gray-50/50">
          <div class="flex items-center justify-between">
            <div class="flex items-center flex-1 min-w-0">
              <div
                class="w-8 h-8 bg-gradient-to-br from-gray-500 to-gray-700 rounded-full flex items-center justify-center mr-2 shadow-md"
                aria-hidden="true"
              >
                <span class="text-white text-xs font-bold">{get_user_initial(@current_user_name)}</span>
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold text-gray-900 truncate">{@current_user_name}</p>
                <p class="text-xs font-medium flex items-center">
                  <span class={get_connection_indicator_class(@connected)} aria-hidden="true"></span>
                  <span class={get_connection_text_class(@connected)}>{@connection_status}</span>
                </p>
              </div>
            </div>
            <button
              class="px-3 py-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 transition-all duration-200 rounded-lg hover:shadow-sm text-sm font-medium"
              aria-label="Configurações"
              title="Configurações"
            >
              Config
            </button>
          </div>
        </footer>
      </aside>

      <!-- Mobile/Tablet overlay -->
      <%= if @sidebar_open do %>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 z-10 lg:hidden"
          phx-click="toggle_sidebar"
        ></div>
      <% end %>

    <!-- Área principal do chat -->
      <main
        class="flex-1 h-full lg:h-screen flex flex-col bg-white min-w-0 lg:border-l border-gray-100 overflow-hidden"
        role="main"
        aria-label="Área de chat"
      >
        <!-- Header do Chat - Hidden on mobile/tablet -->
        <header class="hidden lg:flex items-center justify-between px-6 py-4 border-b border-gray-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-sm">
          <div class="flex items-center">
            <div class="flex items-center space-x-3">
              <div class="w-8 h-8 bg-gradient-to-br from-green-500 to-blue-600 rounded-lg flex items-center justify-center shadow-md">
                <span class="text-white text-sm font-bold">CP</span>
              </div>
              <div>
                <h1 class="text-base md:text-lg font-bold text-gray-900">Chat do Pedido</h1>
                <div class="flex items-center mt-0.5">
                  <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
                  <span class="text-xs md:text-sm text-gray-600 font-medium">{@connection_status}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
            <span class="text-xs text-gray-600">{@connection_status}</span>
            <button
              class="px-3 py-2 text-gray-500 hover:text-gray-700 transition-all duration-200 rounded-lg hover:bg-gray-100 hover:shadow-sm text-sm font-medium"
              aria-label="Buscar mensagens"
              title="Buscar mensagens"
              phx-click="toggle_search"
            >
              Buscar
            </button>

            <button
              class="px-3 py-2 text-gray-500 hover:text-gray-700 transition-all duration-200 rounded-lg hover:bg-gray-100 hover:shadow-sm text-sm font-medium"
              aria-label="Configurações"
              title="Configurações"
              phx-click="toggle_settings"
            >
              Config
            </button>
          </div>
        </header>

    <!-- Search Bar -->
        <%= if @search_open do %>
          <div class="mx-3 md:mx-4 mt-2 p-3 bg-blue-50 border border-blue-200 rounded-lg">
            <form phx-submit="search_messages" class="flex items-center space-x-2">
              <span class="text-blue-500 text-sm font-medium">Buscar:</span>
                             <input
                 name="query"
                 placeholder="Buscar mensagens..."
                 class="flex-1 px-3 py-2 text-sm border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white"
                 autocomplete="off"
                 phx-change="search_messages"
                 phx-debounce="300"
               />
              <button
                type="button"
                phx-click="toggle_search"
                class="px-2 py-1 text-blue-500 hover:text-blue-700 transition-colors text-sm font-medium"
                aria-label="Fechar busca"
              >
                Fechar
              </button>
            </form>
          </div>
        <% end %>

    <!-- Error Message -->
        <%= if @message_error do %>
          <div class="mx-3 md:mx-4 lg:mx-6 mt-2 p-3 bg-red-50 border border-red-200 rounded-lg flex items-center justify-between animate-pulse">
            <div class="flex items-center">
              <span class="text-sm text-red-700">{@message_error}</span>
            </div>
            <button phx-click="clear_error" class="text-red-500 hover:text-red-700 transition-colors">
            </button>
          </div>
        <% end %>

    <!-- Barra de Filtro de Tag -->
    <%= if @active_tag_filter do %>
      <div class="px-4 py-2 bg-blue-100 text-blue-800 flex items-center justify-between">
        <span>
          Mostrando mensagens com a tag: <strong class="font-bold">#{@active_tag_filter}</strong>
        </span>
        <button phx-click="clear_tag_filter" class="font-bold text-blue-600 hover:text-blue-800">
          &times; Limpar Filtro
        </button>
      </div>
    <% end %>

    <!-- Messages Container -->
        <div
          id="messages"
          class="flex-1 overflow-y-auto px-4 lg:px-8 py-4 space-y-3 lg:space-y-4 bg-gradient-to-b from-gray-50/30 to-white scroll-smooth min-h-0"
          role="log"
          aria-live="polite"
          aria-label="Mensagens do chat"
        >

    <!-- Load More Button -->
          <%= if @has_more_messages do %>
            <div class="flex justify-center pb-4">
              <button
                phx-click="load_older_messages"
                disabled={@loading_messages}
                class="px-4 py-2 text-sm text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-2 shadow-sm hover:shadow-md"
              >
                <%= if @loading_messages do %>
                  <span>Carregando...</span>
                <% else %>
                  <span>Carregar mensagens anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <!-- Indicador de digitação -->
          <%= if not Enum.empty?(@typing_users) do %>
            <div class="flex justify-start mb-4">
              <div class="bg-gray-100 text-gray-900 rounded-2xl rounded-bl-sm px-4 py-2 max-w-xs">
                <div class="flex items-center space-x-2">
                  <div class="flex space-x-1">
                    <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                    <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                    <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                  </div>
                  <span class="text-sm text-gray-600">
                    <%= format_typing_users(@typing_users) %> digitando...
                  </span>
                </div>
              </div>
            </div>
          <% end %>

          <%= if Enum.empty?(@filtered_messages) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-8 px-4">
              <div class="w-16 h-16 md:w-20 md:h-20 bg-gradient-to-br from-blue-100 to-indigo-100 rounded-full flex items-center justify-center mb-4 md:mb-6 shadow-sm">
                <span class="text-blue-600 text-lg md:text-xl font-bold">CHAT</span>
              </div>
              <h2 class="text-lg md:text-xl font-semibold text-gray-900 mb-2 md:mb-3">Nenhuma mensagem ainda</h2>
              <p class="text-gray-600 max-w-md text-sm md:text-base">
                Seja o primeiro a enviar uma mensagem neste chat do pedido!
              </p>
            </div>
          <% else %>
            <%= for msg <- @filtered_messages do %>
              <%= if is_system_message?(msg) do %>
                <div class="flex justify-center my-3">
                  <div class="bg-gray-100 text-gray-600 text-sm px-4 py-2 rounded-full shadow-sm border">
                    <%= if is_join_notification?(msg) do %>
                      <span class="text-green-600">●</span> <%= msg.text %>
                    <% else %>
                      <span class="text-gray-500">●</span> <%= msg.text %>
                    <% end %>
                    <span class="text-xs text-gray-400 ml-2">
                      <%= format_time(msg.inserted_at) %>
                    </span>
                  </div>
                </div>
              <% else %>
              <div
                class={"flex mb-2 " <> if(msg.sender_id == @current_user_id, do: "justify-end", else: "justify-start")}
                role="article"
                aria-label={"Mensagem de " <> msg.sender_name}
              >
                <div class={
                  "relative max-w-[85%] md:max-w-md lg:max-w-2xl xl:max-w-4xl px-4 lg:px-6 py-3 lg:py-4 rounded-2xl shadow-md transition-all duration-200 " <>
                  get_message_color(msg.sender_id, @current_user_id, msg.sender_name)
                }>
                  <%= if msg.sender_id != @current_user_id do %>
                    <div class={"text-xs font-semibold mb-1 " <> get_username_color(msg.sender_id, msg.sender_name)}>{msg.sender_name}</div>
                  <% end %>

                  <%= if is_reply_message?(msg) do %>
                    <% original_preview = build_original_message_preview(msg.reply_to, @messages) %>
                    <%= if original_preview do %>
                      <div class="bg-blue-50 border-l-4 border-blue-400 pl-3 pr-2 py-2 mb-3 rounded-r-lg">
                        <div class="flex items-start justify-between">
                          <div class="flex-1 min-w-0">
                            <div class="text-xs font-medium text-blue-700 mb-1">
                              Respondendo à <span class={"font-medium " <> get_username_color(msg.reply_to, original_preview.sender_name)}>{original_preview.sender_name}</span>:
                            </div>
                            <div class="text-sm text-blue-600 italic truncate">
                              "{original_preview.text}"
                            </div>
                          </div>
                          <button
                            class="text-xs text-blue-500 hover:text-blue-700 transition-colors ml-2 flex-shrink-0"
                            phx-click="jump_to_message"
                            phx-value-message_id={original_preview.id}
                            title="Ir para mensagem original"
                          >
                            Ir para original
                          </button>
                        </div>
                      </div>
                    <% else %>
                      <div class="bg-gray-200 bg-opacity-50 border-l-2 border-gray-400 pl-2 mb-2 text-sm italic">
                        Respondendo à mensagem
                      </div>
                    <% end %>
                  <% end %>

                  <%= if is_audio_message?(msg) do %>
                    <div
                      id={"whatsapp-audio-player-#{msg.id}"}
                      phx-hook="WhatsAppAudioPlayer"
                      data-audio-url={msg.audio_url}
                      data-audio-duration={msg.audio_duration || 0}
                      class="whatsapp-audio-container my-2"
                    >
                      <!-- Player será renderizado pelo JavaScript Hook -->
                    </div>
                  <% else %>
                    <%= unless msg.tipo == "imagem" and msg.text == "Imagem enviada" do %>
                      <div class="text-base lg:text-lg break-words leading-relaxed">
                        <%= render_message_with_tags(msg) %>
                      </div>
                    <% end %>
                  <% end %>

                  <%= if has_image?(msg) do %>
                    <img
                      src={msg.image_url}
                      class="w-24 h-24 md:w-32 md:h-32 lg:w-40 lg:h-40 object-cover rounded-lg cursor-pointer hover:scale-105 transition mt-2"
                      phx-click="show_image"
                      phx-value-url={msg.image_url}
                      alt="Imagem enviada"
                      loading="eager"
                    />
                  <% end %>

                  <!-- Preview de documento -->
                  <%= if has_document?(msg) do %>
                    <div class="document-preview mt-2 fade-in">
                      <div class="document-icon bg-blue-100">
                        <span class="text-xl">{get_document_icon(msg.document_name || "documento")}</span>
                      </div>
                      <div class="document-info">
                        <div class="document-name">
                          {msg.document_name || "Documento"}
                        </div>
                        <div class="document-size">
                          {get_document_type(msg.document_name || "")} •
                          <%= if msg.document_size do %>
                            {format_file_size(msg.document_size)}
                          <% else %>
                            Tamanho desconhecido
                          <% end %>
                        </div>
                      </div>
                      <a
                        href={msg.document_url}
                        target="_blank"
                        class="flex items-center justify-center w-10 h-10 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-all"
                        title="Baixar documento"
                      >
                        <span>↓</span>
                      </a>
                    </div>
                  <% end %>

                  <!-- Preview de link -->
                  <%= if has_link_preview?(msg) do %>
                    <div class="link-preview mt-2 fade-in">
                      <%= if msg.link_preview_image && msg.link_preview_image != "" do %>
                        <img
                          src={msg.link_preview_image}
                          class="link-preview-image"
                          alt="Preview do link"
                          loading="lazy"
                        />
                      <% end %>
                      <div class="link-preview-content">
                        <%= if msg.link_preview_title && msg.link_preview_title != "" do %>
                          <div class="link-preview-title">{msg.link_preview_title}</div>
                        <% end %>
                        <%= if msg.link_preview_description && msg.link_preview_description != "" do %>
                          <div class="link-preview-description">{msg.link_preview_description}</div>
                        <% end %>
                        <%= if msg.link_preview_url && msg.link_preview_url != "" do %>
                          <a
                            href={msg.link_preview_url}
                            target="_blank"
                            class="link-preview-url hover:underline"
                          >
                            {String.replace(msg.link_preview_url, ~r/^https?:\/\//, "")}
                          </a>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <div class="flex items-center justify-between mt-1">
                    <div class="flex items-center space-x-2">
                      <!-- Botões de ação MELHORADOS -->
                      <button
                        class="flex items-center space-x-1 text-xs text-gray-400 hover:text-blue-500 transition-colors px-2 py-1 rounded hover:bg-blue-50"
                        phx-click="reply_to_message"
                        phx-value-message_id={msg.id}
                        title="Responder a esta mensagem"
                      >
                        <span></span>
                        <span>Responder</span>
                      </button>

                      <% replies_count = count_message_replies(msg.id, @messages) %>
                      <%= if replies_count do %>
                        <button
                          class="flex items-center space-x-1 text-xs text-gray-400 hover:text-purple-500 transition-colors px-2 py-1 rounded hover:bg-purple-50"
                          phx-click="show_thread"
                          phx-value-message_id={msg.id}
                          title="Ver conversa completa"
                        >
                          <span>Thread</span>
                          <span>{format_thread_reply_counter(replies_count)}</span>
                        </button>
                      <% end %>

                      <%= if is_original_message?(msg) do %>
                        <%= unless count_message_replies(msg.id, @messages) do %>
                          <button
                            class="flex items-center space-x-1 text-xs text-gray-300 hover:text-gray-500 transition-colors px-2 py-1 rounded hover:bg-gray-50"
                            phx-click="reply_to_message"
                            phx-value-message_id={msg.id}
                            title="Iniciar uma discussão"
                          >
                            <span>Discutir</span>
                          </button>
                        <% end %>
                      <% end %>
                    </div>

                    <div class="flex items-center space-x-1">
                      <span class="text-xs text-gray-300">{format_time(msg.inserted_at)}</span>
                      <%= if msg.sender_id == @current_user_id do %>
                        <div class="flex items-center space-x-1">
                          <%= case get_message_status(msg) do %>
                            <% "sent" -> %>
                              <span class="text-xs text-gray-300" title="Enviada">Enviada</span>
                            <% "delivered" -> %>
                              <span class="text-xs text-gray-300" title="Entregue">Entregue</span>
                            <% "read" -> %>
                              <span class="text-xs text-blue-400" title="Lida">Lida</span>
                            <% "system" -> %>
                              <span class="text-xs text-gray-400" title="Sistema">Sistema</span>
                            <% _ -> %>
                              <span class="text-xs text-gray-300" title="Enviada">Enviada</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
              <% end %>
            <% end %>
          <% end %>
        </div>

        <!-- Indicador de resposta -->
        <%= if @replying_to do %>
          <div class="px-4 lg:px-8 py-2 bg-blue-50 border-t border-blue-200">
            <div class="flex items-center justify-between">
              <div class="text-sm text-blue-800">
                <span class="font-medium">Respondendo à:</span>
                <span class="ml-2">
                  <%= if @replying_to.tipo == "imagem" and @replying_to.text == "Imagem enviada" do %>
                    📷 Imagem
                  <% else %>
                    {String.slice(@replying_to.text, 0, 50)}<%= if String.length(@replying_to.text) > 50 do %>...<% end %>
                  <% end %>
                </span>
                <span class="text-blue-600 ml-2">— {@replying_to.sender_name}</span>
              </div>
              <button
                class="text-blue-600 hover:text-blue-800 transition-colors"
                phx-click="cancel_reply"
                title="Cancelar resposta"
              >
                Cancelar
              </button>
            </div>
          </div>
        <% end %>

    <!-- Message Input -->
        <footer class="px-4 lg:px-8 py-4 border-t border-gray-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-lg">
          <form
            id="chat-form"
            phx-submit="send_message"
            phx-drop-target={@uploads.image.ref}
            phx-hook="ChatHook"
            class="flex items-end space-x-2 md:space-x-4"
            role="form"
            aria-label="Enviar mensagem"
          >
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>

              <!-- Preview da imagem MELHORADO -->
              <%= if @uploads[:image] && @uploads.image.entries != [] do %>
                <div class="mb-3 p-3 bg-gray-50 rounded-lg border border-gray-200">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-gray-700">Imagem selecionada:</span>
                    <span class="text-xs text-gray-500">Clique em enviar para compartilhar</span>
                  </div>

                  <div class="flex items-center space-x-3">
                    <%= for entry <- @uploads.image.entries do %>
                      <div class="relative inline-block">
                        <!-- Preview da imagem com fallback -->
                        <div class="relative w-16 h-16 bg-gray-100 rounded-lg border-2 border-blue-200 shadow-sm overflow-hidden">
                          <.live_img_preview
                            entry={entry}
                            class="w-full h-full object-cover"
                          />
                          <!-- Fallback: ícone de imagem quando preview não funciona -->
                          <div class="image-preview-fallback">
                            <span class="text-2xl">IMG</span>
                          </div>
                        </div>

                        <!-- Status da imagem -->
                        <%= if entry.valid? do %>
                          <div class="absolute -top-1 -right-1 w-4 h-4 bg-green-500 rounded-full flex items-center justify-center">
                            <span class="text-white text-xs">✓</span>
                          </div>
                        <% else %>
                          <div class="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full flex items-center justify-center">
                            <span class="text-white text-xs">✗</span>
                          </div>
                        <% end %>

                        <!-- Botão para remover -->
                        <button
                          type="button"
                          phx-click="cancel_upload"
                          phx-value-ref={entry.ref}
                          class="absolute -top-2 -right-2 w-6 h-6 bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors flex items-center justify-center"
                          title="Remover imagem"
                        >
                          <span class="text-xs">×</span>
                        </button>
                      </div>

                      <!-- Info da imagem -->
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900 truncate">{entry.client_name}</p>
                        <p class="text-xs text-gray-500">
                          {format_file_size(entry.client_size)} • {entry.client_type}
                        </p>
                        <%= if entry.valid? do %>
                          <p class="text-xs text-green-600">Pronto para envio</p>
                        <% else %>
                          <p class="text-xs text-red-600">✗ {format_upload_error(entry.errors)}</p>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Preview de documentos -->
              <%= if @uploads[:document] && @uploads.document.entries != [] do %>
                <div class="mb-3 p-3 bg-blue-50 rounded-lg border border-blue-200">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-blue-700">Documento selecionado:</span>
                    <span class="text-xs text-blue-500">Clique em enviar para compartilhar</span>
                  </div>

                  <div class="space-y-2">
                    <%= for entry <- @uploads.document.entries do %>
                      <div class="flex items-center space-x-3 p-2 bg-white rounded-lg border border-blue-200">
                        <!-- Ícone do documento -->
                        <div class="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
                          <span class="text-2xl">{get_document_icon(entry.client_name)}</span>
                        </div>

                        <!-- Info do documento -->
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium text-gray-900 truncate">{entry.client_name}</p>
                          <p class="text-xs text-gray-500">
                            {format_file_size(entry.client_size)} • {get_document_type(entry.client_name)}
                          </p>
                          <%= if entry.valid? do %>
                            <p class="text-xs text-green-600">Pronto para envio</p>
                          <% else %>
                            <p class="text-xs text-red-600">✗ {format_upload_error(entry.errors)}</p>
                          <% end %>
                        </div>

                        <!-- Status e botão remover -->
                        <div class="flex items-center space-x-2">
                          <%= if entry.valid? do %>
                            <div class="w-6 h-6 bg-green-500 rounded-full flex items-center justify-center">
                              <span class="text-white text-xs">✓</span>
                            </div>
                          <% else %>
                            <div class="w-6 h-6 bg-red-500 rounded-full flex items-center justify-center">
                              <span class="text-white text-xs">✗</span>
                            </div>
                          <% end %>

                          <button
                            type="button"
                            phx-click="cancel_upload"
                            phx-value-ref={entry.ref}
                            class="w-6 h-6 bg-red-500 text-white rounded-full hover:bg-red-600 transition-colors flex items-center justify-center"
                            title="Remover documento"
                          >
                            <span class="text-xs">×</span>
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <input
                id="message-input"
                name="message"
                value={@message}
                placeholder="Digite sua mensagem ou anexe uma imagem..."
                class="w-full px-4 lg:px-6 py-3 lg:py-4 pr-12 lg:pr-16 text-base lg:text-lg border border-gray-300 rounded-2xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-gray-400 hover:shadow-md"
                autocomplete="off"
                maxlength={ChatConfig.security_config()[:max_message_length]}
                disabled={not @connected}
                phx-change="update_message"
                phx-keydown="typing_start"
                phx-key="typing_start"
                phx-blur="typing_stop"
                phx-debounce="300"
              />
              <div class="absolute right-3 top-1/2 transform -translate-y-1/2 flex items-center space-x-1">
                <button
                  id="audio-record-button"
                  type="button"
                  phx-click={if @is_recording_audio, do: "stop_audio_recording", else: "start_audio_recording"}
                  class={"p-1.5 transition-all duration-200 rounded-lg hover:shadow-sm " <>
                         if(@is_recording_audio, do: "bg-red-500 text-white animate-pulse", else: "text-gray-400 hover:text-gray-600 hover:bg-gray-100")}
                  aria-label={if @is_recording_audio, do: "Parar gravação", else: "Gravar áudio"}
                  title={if @is_recording_audio, do: "Parar gravação", else: "Gravar áudio"}
                >
                  <span id="audio-record-icon">{if @is_recording_audio, do: "Stop", else: "Rec"}</span>
                </button>

                <!-- Upload de imagens -->
                <label
                  for={@uploads.image.ref}
                  class="p-1.5 text-gray-400 hover:text-gray-600 transition-all duration-200 rounded-lg hover:bg-gray-100 cursor-pointer"
                  aria-label="Anexar imagem"
                  title="Anexar imagem"
                >
                  <span>IMG</span>
                  <.live_file_input upload={@uploads.image} class="hidden" phx-change="validate_image" />
                </label>

                <!-- Upload de documentos -->
                <label
                  for={@uploads.document.ref}
                  class="p-1.5 text-gray-400 hover:text-gray-600 transition-all duration-200 rounded-lg hover:bg-gray-100 cursor-pointer"
                  aria-label="Anexar documento"
                  title="Anexar documento (PDF, Word, Excel, PowerPoint)"
                >
                  <span>DOC</span>
                  <.live_file_input upload={@uploads.document} class="hidden" phx-change="validate_document" />
                </label>
              </div>
            </div>

            <button
              type="submit"
              disabled={
                not @connected or (String.trim(@message || "") == "" and @uploads.image.entries == [] and @uploads.document.entries == [])
              }
              class={
                "px-6 lg:px-8 py-3 lg:py-4 text-base lg:text-lg rounded-2xl focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-3 shadow-md hover:shadow-lg transform hover:scale-105 " <>
                if(not @connected or (String.trim(@message || "") == "" and @uploads.image.entries == [] and @uploads.document.entries == []),
                  do: "bg-gray-400 text-gray-600 opacity-50 cursor-not-allowed",
                  else: "bg-gradient-to-r from-blue-500 to-blue-600 text-white hover:from-blue-600 hover:to-blue-700")
              }
              aria-label="Enviar mensagem"
            >
              <span class="hidden sm:inline">Enviar</span>
              <span class="sm:hidden">→</span>
            </button>
          </form>
        </footer>
      </main>
    </div>

    <!-- MODAL DE THREAD MELHORADO -->
    <%= if @show_thread && @thread_root_message do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-4xl h-[80vh] mx-4 flex flex-col overflow-hidden">
          <!-- Header do Modal -->
          <div class="bg-gradient-to-r from-purple-500 to-blue-600 text-white px-6 py-4 flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <span class="text-2xl">Thread</span>
              <div>
                <h3 class="text-lg font-bold">Thread de Conversa</h3>
                <p class="text-purple-100 text-sm">
                  {length(@thread_replies)} resposta(s) à mensagem de {@thread_root_message.sender_name}
                </p>
              </div>
            </div>
            <button
              phx-click="close_thread"
              class="text-white/80 hover:text-white hover:bg-white/20 rounded-full p-2 transition-all"
              title="Fechar thread"
            >
              ✕
            </button>
          </div>

          <!-- Mensagem Original -->
          <div class="border-b border-gray-200 p-4 bg-purple-50">
            <div class="flex items-start space-x-3">
              <div class={"w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 " <> get_avatar_color(@thread_root_message.sender_id, @thread_root_message.sender_name)}>
                <span class="text-white font-bold text-sm">{get_user_initial(@thread_root_message.sender_name)}</span>
              </div>
              <div class="flex-1 min-w-0">
                                 <div class="flex items-center space-x-2 mb-2">
                   <span class={"font-semibold " <> get_username_color(@thread_root_message.sender_id, @thread_root_message.sender_name)}>{@thread_root_message.sender_name}</span>
                  <span class="text-xs text-gray-500">{format_time(@thread_root_message.inserted_at)}</span>
                  <span class="bg-purple-100 text-purple-800 text-xs px-2 py-1 rounded-full font-medium">Mensagem Original</span>
                </div>
                <%= unless @thread_root_message.tipo == "imagem" and @thread_root_message.text == "Imagem enviada" do %>
                  <div class="text-gray-800 leading-relaxed">
                    <%= if has_mentions?(@thread_root_message) do %>
                      {render_message_with_mention_highlights(@thread_root_message.text)}
                    <% else %>
                      {@thread_root_message.text}
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Lista de Respostas -->
          <div class="flex-1 overflow-y-auto p-4 space-y-4">
            <%= if Enum.empty?(@thread_replies) do %>
              <div class="text-center py-8 text-gray-500">
                <span class="text-4xl mb-4 block">💭</span>
                <p class="text-lg font-medium">Ainda não há respostas</p>
                <p class="text-sm">Seja o primeiro a responder a esta mensagem!</p>
              </div>
            <% else %>
              <%= for {reply, index} <- Enum.with_index(@thread_replies) do %>
                                 <div class="flex items-start space-x-3 group">
                   <div class={"w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 " <> get_avatar_color(reply.sender_id, reply.sender_name)}>
                     <span class="text-white font-bold text-xs">{get_user_initial(reply.sender_name)}</span>
                   </div>
                  <div class="flex-1 min-w-0">
                                         <div class="flex items-center space-x-2 mb-1">
                       <span class={"font-medium " <> get_username_color(reply.sender_id, reply.sender_name)}>{reply.sender_name}</span>
                      <span class="text-xs text-gray-500">{format_time(reply.inserted_at)}</span>
                      <span class="bg-blue-100 text-blue-800 text-xs px-2 py-1 rounded-full">#{index + 1}</span>
                    </div>
                    <div class={
                      "p-3 rounded-xl " <>
                      get_thread_reply_color(reply.sender_id, @current_user_id, reply.sender_name)
                    }>
                      <%= unless reply.tipo == "imagem" and reply.text == "Imagem enviada" do %>
                        <%= if has_mentions?(reply) do %>
                          {render_message_with_mention_highlights(reply.text)}
                        <% else %>
                          {reply.text}
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>

          <!-- Campo de Resposta Rápida -->
          <div class="border-t border-gray-200 p-4 bg-gray-50">
            <form phx-submit="send_thread_reply" class="space-y-3">
              <div class="flex items-start space-x-3">
                <div class="w-8 h-8 bg-gradient-to-br from-gray-500 to-gray-700 rounded-full flex items-center justify-center flex-shrink-0">
                  <span class="text-white font-bold text-xs">{get_user_initial(@current_user_name)}</span>
                </div>
                <div class="flex-1">
                  <textarea
                    name="reply"
                    value={@thread_reply_text}
                    placeholder="Digite sua resposta nesta thread..."
                    class="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-purple-500 focus:border-purple-500 resize-none"
                    rows="3"
                    phx-change="update_thread_reply"
                    maxlength="1000"
                  ></textarea>
                  <div class="flex items-center justify-between mt-2">
                    <span class="text-xs text-gray-500">
                      {String.length(@thread_reply_text || "")}/1000 caracteres
                    </span>
                    <div class="flex items-center space-x-2">
                      <button
                        type="button"
                        phx-click="close_thread"
                        class="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors text-sm"
                      >
                        Cancelar
                      </button>
                      <button
                        type="submit"
                        disabled={String.trim(@thread_reply_text || "") == ""}
                        class={
                          "px-6 py-2 rounded-lg text-sm font-medium transition-all " <>
                          if(String.trim(@thread_reply_text || "") == "",
                            do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                            else: "bg-gradient-to-r from-purple-500 to-blue-600 text-white hover:from-purple-600 hover:to-blue-700 hover:shadow-lg")
                        }
                      >
                        Responder na Thread
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Modal de Imagem (mantido) -->
    <%= if @modal_image_url do %>
      <div
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
        phx-click="close_image_modal"
      >
        <div class="relative" phx-click="stopPropagation">
          <img
            src={@modal_image_url}
            class="max-h-[80vh] max-w-[90vw] rounded-lg shadow-2xl border-4 border-white"
            alt="Imagem ampliada"
          />
          <button
            class="absolute top-2 right-2 bg-white/80 rounded-full p-2 text-gray-700 hover:text-red-600"
            phx-click="close_image_modal"
          >
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  # Funções auxiliares privadas

  # Funções para verificação assertiva de tipos de mensagem
  defp is_system_message?(%{is_system: true}), do: true
  defp is_system_message?(_), do: false

  defp is_join_notification?(%{notification_type: "join"}), do: true
  defp is_join_notification?(_), do: false

  defp is_reply_message?(%{is_reply: true, reply_to: reply_to}) when not is_nil(reply_to), do: true
  defp is_reply_message?(%{reply_to: reply_to}) when not is_nil(reply_to), do: true
  defp is_reply_message?(_), do: false

  defp is_audio_message?(%{tipo: "audio", audio_url: url}) when not is_nil(url), do: true
  defp is_audio_message?(_), do: false



  defp has_mentions?(%{has_mentions: true}), do: true
  defp has_mentions?(_), do: false

  defp has_image?(%{image_url: url}) when not is_nil(url) and url != "", do: true
  defp has_image?(_), do: false

  # Verificação assertiva para documentos seguindo anti-padrões do Elixir
  defp has_document?(%{document_url: url}) when not is_nil(url) and url != "", do: true
  defp has_document?(_), do: false

  # Verificação assertiva para preview de links seguindo anti-padrões do Elixir
  defp has_link_preview?(%{link_preview_url: url}) when not is_nil(url) and url != "", do: true
  defp has_link_preview?(_), do: false

  defp is_original_message?(%{is_reply: false, reply_to: nil}), do: true
  defp is_original_message?(%{reply_to: nil}), do: true
  defp is_original_message?(_), do: false

  defp get_message_status(%{status: status}) when not is_nil(status), do: status
  defp get_message_status(_), do: "sent"

  defp generate_unique_filename(original_name) do
    timestamp = System.system_time(:millisecond)
    uuid = UUID.uuid4() |> String.slice(0, 8)
    extension = Path.extname(original_name)
    base_name = Path.basename(original_name, extension) |> String.slice(0, 20)

    "#{timestamp}_#{uuid}_#{base_name}#{extension}"
  end

  defp process_image_upload(socket) do
    require Logger

    case socket.assigns.uploads.image.entries do
      [] ->
        Logger.debug("Nenhuma imagem para upload - entries vazio")
        nil

      entries ->
        Logger.debug("Processando upload de imagem - #{length(entries)} entries")
        Logger.debug("Upload entries: #{inspect(Enum.map(entries, &%{name: &1.client_name, valid: &1.valid?}))}")

        result = consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
          filename = generate_unique_filename(entry.client_name)
          Logger.debug("Upload de imagem: #{entry.client_name} -> #{filename}")
          Logger.debug("Arquivo temporário: #{path}")

          case App.Minio.upload_file(path, filename) do
            {:ok, url} ->
              Logger.info("Imagem enviada com sucesso: #{url}")
              {:ok, url}
            {:error, reason} ->
              Logger.error("Falha no upload da imagem: #{inspect(reason)}")
              {:ok, nil}
          end
        end)

                Logger.debug("Resultado do consume_uploaded_entries: #{inspect(result)}")

        case List.first(result) do
          url when is_binary(url) and url != "" and url != nil ->
            Logger.debug("URL final extraída: #{inspect(url)}")
            url
          {:ok, url} when is_binary(url) ->
            Logger.debug("URL extraída de tupla: #{inspect(url)}")
            url
          other ->
            Logger.debug("Resultado inesperado: #{inspect(other)}")
            nil
        end
    end
  end

  defp process_recorded_audio(socket, audio_params) do
    try do
      audio_url = upload_audio_from_base64(audio_params)

      params = %{
        text: format_audio_message_text(audio_params),
        sender_id: socket.assigns.current_user_id,
        sender_name: socket.assigns.current_user_name,
        order_id: socket.assigns.order_id,
        tipo: "audio",
        audio_url: audio_url,
        audio_duration: audio_params["duration"] || 0,
        audio_mime_type: audio_params["mime_type"] || "audio/webm",
        status: "sent"
      }

      case App.Chat.create_message(params) do
        {:ok, message} ->
          topic = "order:#{socket.assigns.order_id}"
          Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})

          updated_socket = socket
          |> assign(:is_recording_audio, false)
          |> put_flash(:info, "Áudio enviado com sucesso!")

          {:ok, updated_socket}

        {:error, _changeset} ->
          {:error, "Falha ao salvar mensagem de áudio"}
      end
    rescue
      error ->
        require Logger
        Logger.error("Error processing recorded audio: #{inspect(error)}")
        {:error, "Erro interno ao processar áudio"}
    end
  end

  defp upload_audio_from_base64(audio_params) do
    require Logger

    audio_data = audio_params["audio_data"]
    mime_type = audio_params["mime_type"] || "audio/webm"

    Logger.debug("Processando upload de áudio: #{mime_type}")

    file_extension = extract_audio_file_extension(mime_type)
    filename = generate_audio_filename(file_extension)

    try do
      binary_data = Base.decode64!(audio_data)
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
    rescue
      error ->
        Logger.error("Erro no processamento de áudio: #{inspect(error)}")
        reraise error, __STACKTRACE__
    end
  end

  defp generate_audio_filename(extension) do
    timestamp = System.system_time(:millisecond)
    uuid = UUID.uuid4() |> String.slice(0, 8)
    "audio_#{timestamp}_#{uuid}.#{extension}"
  end

  defp create_temp_audio_file(filename, binary_data) do
    temp_path = System.tmp_dir!() |> Path.join(filename)

    case File.write(temp_path, binary_data) do
      :ok -> temp_path
      {:error, reason} ->
        raise "Falha ao criar arquivo temporário: #{reason}"
    end
  end

  defp extract_audio_file_extension(mime_type) do
    case mime_type do
      "audio/webm" <> _ -> "webm"
      "audio/mp4" -> "mp4"
      "audio/wav" -> "wav"
      "audio/mp3" -> "mp3"
      _ -> "webm"
    end
  end

  defp format_audio_message_text(%{"duration" => duration}) when is_integer(duration) do
    minutes = div(duration, 60)
    seconds = rem(duration, 60)
    "Áudio #{String.pad_leading("#{minutes}", 2, "0")}:#{String.pad_leading("#{seconds}", 2, "0")}"
  end

  defp format_audio_message_text(_), do: "Mensagem de áudio"



    # Envia uma mensagem no chat e atualiza o estado do socket.
  # Para indicadores de digitação e limpa o campo de mensagem quando bem-sucedida.
  # Em caso de erro, define uma mensagem de erro no socket.
  defp send_chat_message(socket, text, image_url) do
    # Parar indicador de digitação ao enviar mensagem
    if socket.assigns[:is_typing] do
      user_name = socket.assigns.current_user_name
      topic = socket.assigns.topic
      Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_stop, user_name})
    end

    # Preparar parâmetros da mensagem com lógica melhorada
    has_image = not is_nil(image_url) and image_url != ""
    text_empty = is_nil(text) or String.trim(text || "") == ""

    message_type = if text_empty and has_image, do: "imagem", else: "mensagem"
    message_text = cond do
      text_empty and has_image -> "Imagem enviada"
      text_empty -> "Mensagem vazia"  # Fallback para evitar erro de validação
      true -> text
    end

    params = %{
      text: message_text,
      sender_id: socket.assigns.current_user_id,
      sender_name: socket.assigns.current_user_name,
      order_id: socket.assigns.order_id,
      tipo: message_type,
      image_url: image_url,
      status: "sent"
    }

    # Adicionar reply_to se estiver respondendo
    params = case socket.assigns[:replying_to] do
      %{id: reply_id} -> Map.put(params, :reply_to, reply_id)
      _ -> params
    end

    require Logger
    Logger.debug("ANÁLISE DE UPLOAD:")
    Logger.debug("  - image_url: #{inspect(image_url)}")
    Logger.debug("  - has_image: #{has_image}")
    Logger.debug("  - text_empty: #{text_empty}")
    Logger.debug("  - message_type: #{message_type}")
    Logger.debug("  - message_text: #{inspect(message_text)}")
    Logger.debug("Parâmetros da mensagem: #{inspect(params)}")

    case App.Chat.create_message(params) do
      {:ok, message} ->
        Logger.info("Mensagem criada com sucesso: #{message.id}")
        # Publicar a mensagem via PubSub
        topic = "order:#{socket.assigns.order_id}"
        Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})

        {:noreply,
         socket
         |> assign(:message, "")
         |> assign(:message_error, nil)
         |> assign(:is_typing, false)
         |> assign(:replying_to, nil)
         |> push_event("clear-message-input", %{})}

      {:error, changeset} ->
        Logger.error("Erro ao criar mensagem - Changeset: #{inspect(changeset)}")
        Logger.error("Erros do changeset: #{inspect(changeset.errors)}")

        error_message = case changeset.errors do
          [] -> "Erro desconhecido ao enviar mensagem"
          errors -> "Erro de validação: #{format_errors(errors)}"
        end

        {:noreply, assign(socket, :message_error, error_message)}
    end
  end

  defp initialize_chat_socket(socket, order_id) do
    topic = "order:#{order_id}"

    setup_presence_if_connected(socket, topic, order_id)
    order = load_order_data(order_id)
    {messages, has_more} = load_messages(order_id)

    setup_socket_assigns(socket, order_id, topic, order, messages, has_more)
  end

  defp setup_presence_if_connected(socket, topic, _order_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, topic)

      current_user_name = resolve_current_user_name(socket)
      current_user_id = resolve_unique_user_id(socket)

      presence_key = current_user_id

      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{current_user_id}")
      Phoenix.PubSub.subscribe(App.PubSub, "sound_notifications:#{current_user_id}")
      Phoenix.PubSub.subscribe(App.PubSub, "mentions:#{current_user_id}")

      user_data = %{
        user_id: current_user_id,
        name: current_user_name,
        joined_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        user_agent: get_connect_info(socket, :user_agent) || "Unknown",
        socket_id: socket.id,
        pid: inspect(self())
      }

      require Logger
      Logger.debug("ChatLive - Tracking presence for user: #{current_user_name} (#{current_user_id}) on topic: #{topic}")

            case Presence.track(self(), topic, presence_key, user_data) do
        {:ok, _} ->
          Logger.debug("ChatLive - Presence tracking successful for user: #{current_user_id}")

          # CORREÇÃO: Agendar recarregamento das mensagens históricas após conexão
          Process.send_after(self(), :reload_historical_messages, 500)
          Logger.info("ChatLive - Scheduled historical message reload for connected user")

          :ok
        {:error, reason} ->
          Logger.warning("ChatLive - Failed to track presence for user #{current_user_id}: #{inspect(reason)}")
      end
    end
  end

  defp load_order_data(order_id) do
    case App.Orders.get_order(order_id) do
      nil ->
        %{
          "orderId" => order_id,
          "status" => "Não encontrado",
          "customerName" => "N/A",
          "amount" => "0",
          "deliveryType" => "N/A",
          "deliveryDate" => ""
        }
      order -> order
    end
  end

  defp load_messages(order_id) do
    case App.Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit()) do
      {:ok, msgs, more} -> {msgs, more}
    end
  end

  defp setup_socket_assigns(socket, order_id, topic, order, messages, has_more) do
    presences = Presence.list(topic)
    users_online =
      try do
        extract_unique_users_from_presences(presences)
      rescue
        error ->
          require Logger
          Logger.error("Error extracting users from presences: #{inspect(error)}")

          []
      end

    current_user_name = resolve_current_user_name(socket)
    current_user_id = resolve_unique_user_id(socket)

        # INICIALIZAÇÃO: Notificações começam vazias, então filtered_messages = messages
    system_notifications = []
    all_messages = get_all_messages_with_notifications(messages, system_notifications)

    socket
    |> assign(:order_id, order_id)
    |> assign(:order, order)
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
    |> assign(:presences, presences)
    |> assign(:message, "")
    |> assign(:users_online, users_online)
    |> assign(:current_user_name, current_user_name)
    |> assign(:current_user_id, current_user_id)
    |> assign(:connected, connected?(socket))
    |> assign(:connection_status, if(connected?(socket), do: "Conectado", else: "Desconectado"))
    |> assign(:topic, topic)
    |> assign(:loading_messages, false)
    |> assign(:message_error, nil)
    |> assign(:modal_image_url, nil)
    |> assign(:typing_users, MapSet.new())
    |> assign(:is_typing, false)
    |> assign(:sidebar_open, false)
    |> assign(:search_open, false)
    |> assign(:settings_open, false)
    |> assign(:filtered_messages, all_messages)  # ATUALIZAÇÃO: Usar função helper
    |> assign(:system_notifications, system_notifications)
    |> assign(:replying_to, nil)
    |> assign(:thread_messages, [])
    |> assign(:thread_root_message, nil)
    |> assign(:thread_replies, [])
    |> assign(:thread_reply_text, "")
    |> assign(:show_thread, false)
    |> assign(:mentions, [])
    |> assign(:show_mentions, false)
    |> assign(:is_recording_audio, false)
    |> allow_upload(:image,
      accept: ~w(.jpg .jpeg .png .gif),
      max_entries: 1,
      max_file_size: 5_000_000
    )
    |> allow_upload(:audio,
      accept: ~w(.webm .mp3 .wav .m4a),
      max_entries: 1,
      max_file_size: 10_000_000
    )
    |> allow_upload(:document,
      accept: ~w(.pdf .doc .docx .xls .xlsx .ppt .pptx),
      max_entries: 1,
      max_file_size: 25_000_000
    )
  end

  defp extract_unique_users_from_presences(presences) do
    unique_users = presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: user_metas} ->
      Enum.map(user_metas, &extract_user_info_from_meta/1)
    end)
    |> Enum.uniq_by(fn {user_id, _name} -> user_id end)
    |> Enum.map(fn {_user_id, display_name} -> display_name end)
    |> Enum.sort()

    log_user_extraction_result(unique_users)
    unique_users
  end

  defp extract_user_info_from_meta(%{name: name, user_id: user_id})
    when is_binary(name) and is_binary(user_id), do: {user_id, name}

  defp extract_user_info_from_meta(%{"name" => name, "user_id" => user_id})
    when is_binary(name) and is_binary(user_id), do: {user_id, name}

  defp extract_user_info_from_meta(%{name: name}) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(%{"name" => name}) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(name) when is_binary(name), do: {name, name}

  defp extract_user_info_from_meta(_) do
    default_user = ChatConfig.default_username()
    {default_user, default_user}
  end

  defp log_user_extraction_result(users) do
    require Logger
    Logger.debug("ChatLive - Extracted #{length(users)} unique users from presences: #{inspect(users)}")
  end

  defp load_older_messages_async(socket) do
    order_id = socket.assigns.order_id
    current_count = length(socket.assigns.messages)

    Task.start(fn ->
      case App.Chat.list_messages_for_order(
             order_id,
             ChatConfig.pagination_config()[:default_limit],
             current_count
           ) do
        {:ok, older_messages, has_more} ->
          send(self(), {:older_messages_loaded, older_messages, has_more})
      end
    end)

    socket
  end

  defp get_user_initial(user) when is_binary(user) and user != "" do
    user |> String.first() |> String.upcase()
  end

  defp get_user_initial(_), do: "U"

  defp get_status_class(status) do
    base_classes = "px-3 py-1.5 text-xs font-semibold rounded-full border shadow-sm"

    case String.downcase(status || "") do
      "ativo" -> "#{base_classes} bg-green-100 text-green-800 border-green-200"
      "pendente" -> "#{base_classes} bg-yellow-100 text-yellow-800 border-yellow-200"
      "cancelado" -> "#{base_classes} bg-red-100 text-red-800 border-red-200"
      "concluído" -> "#{base_classes} bg-blue-100 text-blue-800 border-blue-200"
      _ -> "#{base_classes} bg-gray-100 text-gray-800 border-gray-200"
    end
  end

  defp get_connection_indicator_class(connected) do
    base_classes = "w-1.5 h-1.5 rounded-full mr-1.5"

    if connected,
      do: "#{base_classes} bg-green-500 animate-pulse",
      else: "#{base_classes} bg-red-500"
  end

  defp get_connection_text_class(connected) do
    if connected, do: "text-green-600", else: "text-red-600"
  end

  defp format_currency(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {float_amount, _} -> :erlang.float_to_binary(float_amount, decimals: 2)
      :error -> amount
    end
  end

  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_date(date_string) when is_binary(date_string) and date_string != "" do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        "#{String.pad_leading("#{datetime.day}", 2, "0")}/#{String.pad_leading("#{datetime.month}", 2, "0")}/#{datetime.year}"

      _ ->
        date_string
    end
  end

  defp format_date(_), do: "Data não disponível"

  defp format_time(datetime) do
    case datetime do
      %DateTime{} ->
        "#{String.pad_leading("#{datetime.hour}", 2, "0")}:#{String.pad_leading("#{datetime.minute}", 2, "0")}"

      _ ->
        "Hora não disponível"
    end
  end

  defp format_typing_users(typing_users) do
    user_list = MapSet.to_list(typing_users)

    case length(user_list) do
      0 -> ""
      1 -> List.first(user_list)
      2 -> "#{Enum.at(user_list, 0)} e #{Enum.at(user_list, 1)}"
      _ -> "#{length(user_list)} usuários"
    end
  end




  defp render_message_with_mention_highlights(text) do
    Regex.replace(~r/@(\w+)/, text, fn _match, username ->
      ~s(<span class="bg-blue-100 text-blue-800 px-1 rounded font-medium">@#{username}</span>)
    end)
    |> Phoenix.HTML.raw()
  end


  defp count_message_replies(message_id, messages) do
    reply_count = Enum.count(messages, fn msg ->
      case msg do
        %{is_system: true} -> false
        %{reply_to: reply_to} -> reply_to == message_id
        _ -> false
      end
    end)

    if reply_count > 0, do: reply_count, else: false
  end

  defp build_original_message_preview(reply_to_id, messages) do
    case Enum.find(messages, fn msg -> msg.id == reply_to_id end) do
      nil -> nil
      original_message ->
        preview_text = truncate_message_text(original_message.text, 80)
        %{
          id: original_message.id,
          text: preview_text,
          sender_name: original_message.sender_name,
          full_text: original_message.text
        }
    end
  end





  defp truncate_message_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end


  defp format_thread_reply_counter(reply_count) when is_integer(reply_count) do
    case reply_count do
      1 -> "1 resposta"
      count when count > 1 -> "#{count} respostas"
      _ -> "Thread"
    end
  end

  defp format_thread_reply_counter(_), do: "Thread"


  defp get_user_color(user_id, user_name) do

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


  defp get_message_color(sender_id, current_user_id, _sender_name) do
    if sender_id == current_user_id do

      "rounded-br-sm text-gray-800" <> " " <> "bg-[#DCF8C6]"
    else

      "bg-white border border-gray-200 text-gray-900 rounded-bl-sm shadow-sm"
    end
  end


  defp get_avatar_color(user_id, user_name) do
    user_color = get_user_color(user_id, user_name)
    user_color.avatar
  end


  defp get_thread_reply_color(sender_id, current_user_id, _sender_name) do
    if sender_id == current_user_id do
      "bg-gradient-to-br from-green-50 to-green-100 border-l-4 border-[#25D366]"
    else

      "bg-gray-50 border-l-4 border-gray-300"
    end
  end


  defp get_username_color(user_id, user_name) do

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


  defp process_presence_notifications(diff, topic, current_user_id) do
    notification_start_time = System.monotonic_time(:microsecond)
    require Logger

    user_joins = Map.get(diff, :joins, %{})
    user_leaves = Map.get(diff, :leaves, %{})

    Logger.debug("Processando presence diff - Joins: #{map_size(user_joins)}, Leaves: #{map_size(user_leaves)}")

    # Processar joins diretamente (sem Task aninhada)
    if map_size(user_joins) > 0 do
      broadcast_user_join_notifications(user_joins, topic, current_user_id)
    end

    # Processar leaves diretamente (sem Task aninhada)
    if map_size(user_leaves) > 0 do
      broadcast_user_leave_notifications(user_leaves, topic, current_user_id)
    end

    log_presence_processing_time(notification_start_time, user_joins, user_leaves)
  end

  @doc """
  Processa notificações de entrada de usuários seguindo anti-padrões do Elixir.
  Implementa sistema robusto de debounce para evitar spam de notificações.
  """
  @spec broadcast_user_join_notifications(map(), String.t(), String.t()) :: :ok
  defp broadcast_user_join_notifications(user_joins, topic, _current_user_id) do
    require Logger

    Enum.each(user_joins, fn {user_id, %{metas: [user_meta | _]}} ->
      user_name = extract_user_name_from_meta(user_meta)

      Logger.debug("User join detected: #{user_name} (#{user_id}) em #{topic}")

      # Pattern matching assertivo para validação de entrada usando and ao invés de &&
      case should_create_join_notification?(user_id, user_name) do
        true ->
          process_user_join_notification(user_id, user_name, topic)
        false ->
          Logger.debug("🚫 Notificação de entrada ignorada para #{user_name}")
      end
    end)
  end

  @doc """
  Processa notificação de entrada válida seguindo anti-padrões do Elixir.
  Cria notificação após validação de debounce.
  """
  @spec process_user_join_notification(String.t(), String.t(), String.t()) :: :ok
  defp process_user_join_notification(user_id, user_name, topic) do
    require Logger

          Logger.debug("Criando notificação de entrada para: #{user_name}")
    create_fast_system_notification(topic, "#{user_name} entrou na conversa", "join", user_id)
  end

  @doc """
  Processa notificações de saída de usuários seguindo anti-padrões do Elixir.
  Implementa cache robusto e pattern matching assertivo.
  """
  @spec broadcast_user_leave_notifications(map(), String.t(), String.t()) :: :ok
  defp broadcast_user_leave_notifications(user_leaves, topic, _current_user_id) do
    require Logger

    Enum.each(user_leaves, fn {user_id, %{metas: [user_meta | _]}} ->
      user_name = extract_user_name_from_meta(user_meta)
      current_time = System.system_time(:second)

      Logger.debug("User leave detected: #{user_name} (#{user_id}) em #{topic}")

      # Pattern matching assertivo para validar saída usando and ao invés de &&
      case should_create_leave_notification?(user_id, user_name, current_time) do
        true ->
          process_user_leave_notification(user_id, user_name, topic, current_time)
        false ->
          Logger.debug("🚫 Notificação de saída ignorada para #{user_name}")
      end
    end)
  end

  @doc """
  Extrai nome do usuário dos metadados usando pattern matching assertivo.
  Normaliza retornos conforme anti-padrões do Elixir.
  """
  @spec extract_user_name_from_meta(map()) :: String.t()
  defp extract_user_name_from_meta(user_meta) do
    # Pattern matching assertivo para diferentes formatos de metadados
    case user_meta do
      %{name: name} when is_binary(name) and name != "" -> name
      %{"name" => name} when is_binary(name) and name != "" -> name
      %{username: username} when is_binary(username) and username != "" -> username
      %{"username" => username} when is_binary(username) and username != "" -> username
      _ -> "Usuário desconhecido"
    end
  end

  @doc """
  Verifica se deve criar notificação de saída seguindo anti-padrões do Elixir.
  Evita spam de notificações usando pattern matching assertivo.
  """
  @spec should_create_leave_notification?(String.t(), String.t(), integer()) :: boolean()
    defp should_create_leave_notification?(user_id, user_name, current_time) do
    require Logger

    # Pattern matching assertivo para verificar última saída
    case Process.get({:last_leave, user_id}) do
      last_leave_time when is_integer(last_leave_time) ->
        time_diff = current_time - last_leave_time

        # Usar and ao invés de && conforme anti-padrões
        if time_diff < 10 do
          Logger.debug("Saída muito rápida para #{user_name}: #{time_diff}s - evitando spam")
          false
        else
          true
        end

      _ ->
        true
    end
  end

  @doc """
  Processa notificação de saída válida seguindo anti-padrões do Elixir.
  Atualiza cache e cria notificação.
  """
  @spec process_user_leave_notification(String.t(), String.t(), String.t(), integer()) :: :ok
  defp process_user_leave_notification(user_id, user_name, topic, current_time) do
    require Logger

    Logger.debug("Criando notificação de saída para: #{user_name}")

    # Atualizar cache de saída
    Process.put({:last_leave, user_id}, current_time)

    create_fast_system_notification(topic, "#{user_name} saiu da conversa", "leave", user_id)
  end

  @doc """
  Registra tempo de processamento de notificações seguindo anti-padrões do Elixir.
  Inclui limpeza periódica de cache para evitar memory leaks.
  """
  @spec log_presence_processing_time(integer(), map(), map()) :: :ok
  defp log_presence_processing_time(start_time, user_joins, user_leaves) do
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    require Logger
    Logger.debug("Presence notifications processed in #{Float.round(duration_ms, 2)}ms - Joins: #{map_size(user_joins)}, Leaves: #{map_size(user_leaves)}")

    # Limpeza periódica de cache para evitar memory leaks (pattern matching assertivo)
    case :rand.uniform(100) do
      n when n <= 5 -> # 5% de chance de limpeza
        cleanup_notification_cache()
      _ ->
        :ok
    end
  end

  @doc """
  Limpa cache de notificações antigas seguindo anti-padrões do Elixir.
  Remove entradas mais antigas que 5 minutos para evitar memory leaks.
  """
  @spec cleanup_notification_cache() :: :ok
  defp cleanup_notification_cache() do
    require Logger
    current_time = System.system_time(:second)
    cutoff_time = current_time - 300 # 5 minutos

    # Pattern matching assertivo para limpeza de cache
    process_dictionary_keys = Process.get_keys()

    cleaned_count = process_dictionary_keys
    |> Enum.filter(&is_notification_cache_key?/1)
    |> Enum.filter(&is_cache_entry_expired?(&1, cutoff_time))
    |> Enum.map(&Process.delete/1)
    |> length()

    if cleaned_count > 0 do
      Logger.debug("🧹 Cache de notificações limpo: #{cleaned_count} entradas removidas")
    end
  end

  @doc """
  Verifica se chave é do cache de notificações usando pattern matching assertivo.
  """
  @spec is_notification_cache_key?(term()) :: boolean()
  defp is_notification_cache_key?(key) do
    # Pattern matching assertivo para tipos de cache
    case key do
      {:last_join, _user_id} -> true
      {:last_leave, _user_id} -> true
      _ -> false
    end
  end

  @doc """
  Verifica se entrada do cache expirou usando pattern matching assertivo.
  """
  @spec is_cache_entry_expired?(term(), integer()) :: boolean()
  defp is_cache_entry_expired?(key, cutoff_time) do
    case Process.get(key) do
      timestamp when is_integer(timestamp) and timestamp < cutoff_time -> true
      _ -> false
    end
  end

  defp create_fast_system_notification(topic, message_text, notification_type, user_id) do
    timing_start = System.monotonic_time(:microsecond)
    require Logger

    order_id = extract_order_id_fast(topic)
    system_message = build_system_message(message_text, notification_type, user_id, order_id)

    Logger.debug("Broadcasting system notification: #{message_text} para topic: #{topic}")

    try do
      Phoenix.PubSub.broadcast!(App.PubSub, topic, {:system_notification, system_message})
      Logger.debug(" Broadcast realizado com sucesso para: #{topic}")
    rescue
      error ->
        Logger.error("Erro no broadcast: #{inspect(error)}")
        reraise error, __STACKTRACE__
    end

    log_notification_timing(timing_start, notification_type, message_text)
  end

  defp extract_order_id_fast(topic) do
    binary_part(topic, 6, byte_size(topic) - 6)
  end

  defp build_system_message(message_text, notification_type, user_id, order_id) do
    %{
      id: System.unique_integer([:positive]),
      text: message_text,
      sender_id: "system",
      sender_name: "Sistema",
      order_id: order_id,
      tipo: "system_notification",
      notification_type: notification_type,
      target_user_id: user_id,
      inserted_at: DateTime.utc_now(),
      is_system: true,
      reply_to: nil,
      is_reply: false,
      has_mentions: false,
      mentions: [],
      image_url: nil,
      status: "system"
    }
  end

  defp log_notification_timing(start_time, notification_type, message_text) do
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    require Logger
    Logger.debug("FAST notification created and broadcast in #{Float.round(duration_ms, 2)}ms - #{notification_type}: #{message_text}")
  end

  defp resolve_current_user_name(socket) do
    current_user = socket.assigns[:current_user]
    extract_user_name(current_user)
  end

  defp resolve_unique_user_id(socket) do
    current_user = socket.assigns[:current_user]
    user_id = extract_user_id(current_user)

    log_user_id_resolution(user_id, current_user)
    user_id
  end

  defp generate_anonymous_user_id do
    "anonymous_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  defp log_user_id_resolution(user_id, current_user) do
    require Logger
    Logger.debug("ChatLive - User ID resolved: #{user_id} from assigns: #{inspect(current_user)}")
  end

  defp extract_user_name(%{name: name}) when is_binary(name) and name != "", do: name

  defp extract_user_name(%{username: username}) when is_binary(username) and username != "", do: username

  defp extract_user_name(%{"name" => name}) when is_binary(name) and name != "", do: name

  defp extract_user_name(%{"username" => username}) when is_binary(username) and username != "", do: username

  defp extract_user_name(username) when is_binary(username) and username != "", do: username

  defp extract_user_name(_), do: ChatConfig.default_username()

  defp extract_user_id(%{id: id}) when is_binary(id) and id != "", do: id

  defp extract_user_id(%{"id" => id}) when is_binary(id) and id != "", do: id

  defp extract_user_id(%{username: username}) when is_binary(username) and username != "", do: "user_#{username}"

  defp extract_user_id(%{"username" => username}) when is_binary(username) and username != "", do: "user_#{username}"

  defp extract_user_id(username) when is_binary(username) and username != "", do: "legacy_#{username}"

  defp extract_user_id(_), do: generate_anonymous_user_id()

  # Função aprimorada seguindo anti-padrões do Elixir
  defp validate_and_send_enhanced_message(trimmed_text, socket, user_id, image_url, document_url, link_preview_data) do
    case validate_enhanced_message_content(trimmed_text, socket, image_url, document_url) do
      :valid ->
        process_enhanced_message_sending(trimmed_text, socket, user_id, image_url, document_url, link_preview_data)
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # Manter função original para compatibilidade
  defp validate_and_send_message(trimmed_text, socket, user_id, image_url) do
    validate_and_send_enhanced_message(trimmed_text, socket, user_id, image_url, nil, nil)
  end

  # Validação aprimorada para múltiplos tipos de conteúdo
  defp validate_enhanced_message_content(trimmed_text, _socket, image_url, document_url) do
    text_empty = is_nil(trimmed_text) or String.trim(trimmed_text || "") == ""
    has_image = not is_nil(image_url) and image_url != ""
    has_document = not is_nil(document_url) and document_url != ""
    has_attachment = has_image or has_document

    cond do
      text_empty and not has_attachment ->
        {:error, "Mensagem não pode estar vazia sem anexo"}

      not text_empty and String.length(trimmed_text) > ChatConfig.security_config()[:max_message_length] ->
        {:error, "Mensagem muito longa"}

      has_image and has_document ->
        {:error, "Envie apenas um tipo de anexo por vez"}

      true ->
        :valid
    end
  end

  # Manter função original para compatibilidade
  defp validate_message_content(trimmed_text, socket, image_url) do
    validate_enhanced_message_content(trimmed_text, socket, image_url, nil)
  end

  # Processamento aprimorado seguindo anti-padrões do Elixir
  defp process_enhanced_message_sending(trimmed_text, socket, user_id, image_url, document_url, link_preview_data) do
    case RateLimiter.check_message_rate(user_id, trimmed_text) do
      {:ok, :allowed} ->
        handle_successful_enhanced_rate_check(trimmed_text, socket, user_id, image_url, document_url, link_preview_data)

      {:error, reason, wait_time} ->
        error_message = format_rate_limit_error(reason, wait_time)
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  # Manter função original para compatibilidade
  defp process_message_sending(trimmed_text, socket, user_id, image_url) do
    process_enhanced_message_sending(trimmed_text, socket, user_id, image_url, nil, nil)
  end

  # Função aprimorada seguindo anti-padrões do Elixir
  defp handle_successful_enhanced_rate_check(trimmed_text, socket, user_id, image_url, document_url, link_preview_data) do
    result = send_enhanced_chat_message(socket, trimmed_text, image_url, document_url, link_preview_data)

    case result do
      {:noreply, socket} ->
        if is_nil(socket.assigns[:message_error]) do
          RateLimiter.record_message(user_id, trimmed_text)
        end
        result
      _ ->
        result
    end
  end

  # Manter função original para compatibilidade
  defp handle_successful_rate_check(trimmed_text, socket, user_id, image_url) do
    handle_successful_enhanced_rate_check(trimmed_text, socket, user_id, image_url, nil, nil)
  end

  # Função principal de envio de mensagem aprimorada
  defp send_enhanced_chat_message(socket, text, image_url, document_url, link_preview_data) do
    require Logger

    # Determinar tipo de mensagem usando pattern matching assertivo
    message_type = determine_message_type(text, image_url, document_url)

    # Construir parâmetros da mensagem
    base_params = build_base_message_params(socket, text, message_type)
    enhanced_params = add_attachment_params(base_params, image_url, document_url, link_preview_data)

    Logger.debug("Enviando mensagem aprimorada: tipo=#{message_type}")

    case App.Chat.create_message(enhanced_params) do
      {:ok, message} ->
        handle_successful_message_creation(socket, message)
      {:error, changeset} ->
        handle_message_creation_error(socket, changeset)
    end
  end

  # Pattern matching assertivo para determinação do tipo de mensagem
  defp determine_message_type(text, image_url, document_url) do
    cond do
      not is_nil(image_url) and image_url != "" -> "imagem"
      not is_nil(document_url) and document_url != "" -> "documento"
      not is_nil(text) and text != "" -> "mensagem"
      true -> "mensagem"
    end
  end

  # Construção de parâmetros base da mensagem
  defp build_base_message_params(socket, text, message_type) do
    %{
      text: text || "",
      sender_id: socket.assigns.current_user_id,
      sender_name: socket.assigns.current_user_name,
      order_id: socket.assigns.order_id,
      tipo: message_type,
      status: "sent",
      reply_to: get_reply_to_id(socket),
      is_reply: not is_nil(socket.assigns[:replying_to])
    }
  end

  # Adiciona parâmetros de anexos usando pattern matching
  defp add_attachment_params(base_params, image_url, document_url, link_preview_data) do
    base_params
    |> add_image_params(image_url)
    |> add_document_params(document_url)
    |> add_link_preview_params(link_preview_data)
  end

  # Pattern matching para adicionar parâmetros de imagem
  defp add_image_params(params, image_url) when is_binary(image_url) and image_url != "" do
    Map.put(params, :image_url, image_url)
  end
  defp add_image_params(params, _), do: params

  # Pattern matching para adicionar parâmetros de documento
  defp add_document_params(params, document_url) when is_binary(document_url) and document_url != "" do
    params
    |> Map.put(:document_url, document_url)
    |> Map.put(:document_name, extract_filename_from_url(document_url))
    |> Map.put(:document_size, nil) # Será determinado pelo upload
  end
  defp add_document_params(params, _), do: params

  # Pattern matching para adicionar parâmetros de preview de link
  defp add_link_preview_params(params, %{title: title, description: desc, image: image, url: url}) do
    params
    |> Map.put(:link_preview_title, title)
    |> Map.put(:link_preview_description, desc)
    |> Map.put(:link_preview_image, image)
    |> Map.put(:link_preview_url, url)
  end
  defp add_link_preview_params(params, _), do: params

  # Extrai nome do arquivo da URL usando pattern matching
  defp extract_filename_from_url(url) when is_binary(url) do
    url
    |> String.split("/")
    |> List.last()
    |> case do
      nil -> "documento"
      filename -> filename
    end
  end
  defp extract_filename_from_url(_), do: "documento"

  # Pattern matching para obter ID de resposta
  defp get_reply_to_id(%{assigns: %{replying_to: %{id: id}}}), do: id
  defp get_reply_to_id(_), do: nil

  @doc """
  Tratamento de sucesso na criação da mensagem seguindo anti-padrões do Elixir.
  Adiciona logs detalhados para debug de sincronização de imagens.
  """
  @spec handle_successful_message_creation(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp handle_successful_message_creation(socket, message) do
    require Logger

    # Debug detalhado da mensagem criada
    Logger.info("🚀 MENSAGEM CRIADA COM SUCESSO:")
    Logger.info("  ID: #{message.id}")
    Logger.info("  Texto: #{inspect(message.text)}")
    Logger.info("  Tipo: #{message.tipo}")
    Logger.info("  Image URL: #{inspect(message.image_url)}")
    Logger.info("  Document URL: #{inspect(Map.get(message, :document_url))}")
    Logger.info("  Sender: #{message.sender_name} (#{message.sender_id})")
    Logger.info("  Order ID: #{message.order_id}")

    topic = "order:#{socket.assigns.order_id}"

    Logger.info("INICIANDO BROADCAST:")
    Logger.info("  Topic: #{topic}")
    Logger.info("  Broadcast data: #{inspect(%{id: message.id, image_url: message.image_url, tipo: message.tipo})}")

    try do
      Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
      Logger.info("BROADCAST ENVIADO COM SUCESSO para topic: #{topic}")
    rescue
      error ->
        Logger.error("ERRO NO BROADCAST: #{inspect(error)}")
        reraise error, __STACKTRACE__
    end

    Logger.info("Finalizando handle_successful_message_creation")

    {:noreply,
     socket
     |> assign(:message, "")
     |> assign(:replying_to, nil)
     |> assign(:message_error, nil)
     |> put_flash(:info, "Mensagem enviada com sucesso!")}
  end

  # Tratamento de erro na criação da mensagem
  defp handle_message_creation_error(socket, changeset) do
    require Logger

    error_message = format_errors(changeset.errors)
    Logger.error("❌ Falha ao criar mensagem: #{error_message}")

    {:noreply,
     socket
     |> assign(:message_error, error_message)
     |> put_flash(:error, "Erro ao enviar mensagem: #{error_message}")}
  end

  defp format_rate_limit_error(reason, wait_time) do
    case reason do
      :rate_limited -> "Muitas mensagens. Aguarde #{wait_time} segundos."
      :duplicate_spam -> "Não repita a mesma mensagem. Aguarde #{wait_time} segundos."
      :long_message_spam -> "Muitas mensagens longas. Aguarde #{wait_time} segundos."
      _ -> "Rate limit atingido. Aguarde #{wait_time} segundos."
    end
  end

    defp format_upload_error(errors) do
    error_messages = Enum.map(errors, fn
      :too_large -> "Arquivo muito grande (máximo 5MB)"
      :not_accepted -> "Tipo de arquivo não aceito (apenas JPG, PNG, GIF)"
      :too_many_files -> "Apenas uma imagem por vez"
      :external_client_failure -> "Falha no upload"
      error -> "Erro: #{inspect(error)}"
    end)

    case error_messages do
      [single_error] -> single_error
      multiple_errors -> "Problemas: " <> Enum.join(multiple_errors, ", ")
    end
  end

  defp format_file_size(size) when is_integer(size) do
    cond do
      size >= 1_048_576 -> "#{Float.round(size / 1_048_576, 1)}MB"
      size >= 1_024 -> "#{Float.round(size / 1_024, 1)}KB"
      true -> "#{size}B"
    end
  end

  defp format_file_size(_), do: "Tamanho desconhecido"

  # NOVA FUNÇÃO: Mescla mensagens persistentes com notificações temporárias
  defp get_all_messages_with_notifications(messages, system_notifications) do
    # Combinar e ordenar por timestamp
    all_items = messages ++ system_notifications

    Enum.sort(all_items, fn a, b ->
      DateTime.compare(a.inserted_at, b.inserted_at) != :gt
    end)
  end

  # Função para formatar erros do changeset de forma legível
  defp format_errors(errors) do
    errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  @doc """
  Verifica se deve criar notificação de entrada seguindo anti-padrões do Elixir.
  Implementa sistema robusto de debounce para evitar notificações duplicadas.
  Usa pattern matching assertivo e normaliza retornos em função privada.
  """
  @spec should_create_join_notification?(String.t(), String.t()) :: boolean()
  defp should_create_join_notification?(user_id, user_name) do
    require Logger

    current_time = System.system_time(:second)

    # Pattern matching assertivo para diferentes cenários de cache
    case get_user_notification_cache(user_id) do
      {:recent_join, timestamp} when current_time - timestamp < 30 ->
        log_duplicate_notification_blocked(user_name, current_time - timestamp)
        false

      {:recent_leave, timestamp} when current_time - timestamp < 15 ->
        log_quick_reconnection_detected(user_name, current_time - timestamp)
        false

      _ ->
        process_valid_join_notification(user_id, user_name, current_time)
    end
  end

  @doc """
  Obtém cache de notificação do usuário usando pattern matching assertivo.
  Normaliza retornos conforme anti-padrões do Elixir.
  """
  @spec get_user_notification_cache(String.t()) :: {:recent_join, integer()} | {:recent_leave, integer()} | nil
  defp get_user_notification_cache(user_id) do
    join_cache = Process.get({:last_join, user_id})
    leave_cache = Process.get({:last_leave, user_id})

    # Pattern matching assertivo para priorizar eventos mais recentes
    case {join_cache, leave_cache} do
      {join_time, leave_time} when is_integer(join_time) and is_integer(leave_time) ->
        if join_time > leave_time do
          {:recent_join, join_time}
        else
          {:recent_leave, leave_time}
        end

      {join_time, nil} when is_integer(join_time) ->
        {:recent_join, join_time}

      {nil, leave_time} when is_integer(leave_time) ->
        {:recent_leave, leave_time}

      _ ->
        nil
    end
  end

  @doc """
  Processa notificação de entrada válida seguindo anti-padrões do Elixir.
  Atualiza cache e normaliza retorno.
  """
  @spec process_valid_join_notification(String.t(), String.t(), integer()) :: boolean()
  defp process_valid_join_notification(user_id, user_name, current_time) do
    require Logger

    # Atualizar cache de entrada usando and ao invés de &&
    Process.put({:last_join, user_id}, current_time)

    Logger.debug("✅ Notificação de entrada válida para #{user_name}")
    true
  end

  @doc """
  Registra bloqueio de notificação duplicada seguindo anti-padrões do Elixir.
  """
  @spec log_duplicate_notification_blocked(String.t(), integer()) :: :ok
  defp log_duplicate_notification_blocked(user_name, time_diff) do
    require Logger
    Logger.debug("🚫 Notificação duplicada bloqueada para #{user_name}: #{time_diff}s desde última entrada")
  end

  @doc """
  Registra reconexão rápida detectada seguindo anti-padrões do Elixir.
  """
  @spec log_quick_reconnection_detected(String.t(), integer()) :: :ok
  defp log_quick_reconnection_detected(user_name, time_diff) do
    require Logger
    Logger.debug("⚡ Reconexão rápida detectada para #{user_name}: #{time_diff}s - evitando spam")
  end

  defp get_connection_text_class(connected?) do
    if connected?, do: "text-green-600", else: "text-red-500"
  end

  defp render_message_with_tags(message) do
    # Primeiro, escapa o HTML para segurança
    escaped_html = Phoenix.HTML.html_escape(message.text)

    # Extrai o texto seguro da estrutura {:safe, content}
    safe_text = case escaped_html do
      {:safe, content} -> content
      content -> content
    end

    # Depois, substitui #tags por links clicáveis
    text_with_tags = Regex.replace(~r/#([a-zA-Z0-9_]+)/, safe_text, fn _full_match, tag ->
      """
      <a href="#" phx-click="filter_by_tag" phx-value-tag="#{tag}" class="text-blue-600 font-semibold hover:underline">
        ##{tag}
      </a>
      """
    end)

    # Finalmente, marca como seguro para renderizar o HTML
    raw(text_with_tags)
  end

  # Funções auxiliares para documentos - seguindo anti-padrões do Elixir

  @doc """
  Retorna o ícone apropriado para um tipo de documento baseado na extensão.
  Usa pattern matching assertivo ao invés de condicionais complexas.
  """
  @spec get_document_icon(String.t()) :: String.t()
  defp get_document_icon(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> document_icon_for_extension()
  end

  defp get_document_icon(_), do: "📄"

  # Pattern matching assertivo para ícones de documentos
  defp document_icon_for_extension(".pdf"), do: "📕"
  defp document_icon_for_extension(".doc"), do: "📘"
  defp document_icon_for_extension(".docx"), do: "📘"
  defp document_icon_for_extension(".xls"), do: "📗"
  defp document_icon_for_extension(".xlsx"), do: "📗"
  defp document_icon_for_extension(".ppt"), do: "📙"
  defp document_icon_for_extension(".pptx"), do: "📙"
  defp document_icon_for_extension(_), do: "📄"

  @doc """
  Retorna o tipo amigável de documento baseado na extensão.
  Usa pattern matching assertivo conforme anti-padrões do Elixir.
  """
  @spec get_document_type(String.t()) :: String.t()
  defp get_document_type(filename) when is_binary(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> document_type_for_extension()
  end

  defp get_document_type(_), do: "Documento"

  # Pattern matching assertivo para tipos de documentos
  defp document_type_for_extension(".pdf"), do: "PDF"
  defp document_type_for_extension(".doc"), do: "Word"
  defp document_type_for_extension(".docx"), do: "Word"
  defp document_type_for_extension(".xls"), do: "Excel"
  defp document_type_for_extension(".xlsx"), do: "Excel"
  defp document_type_for_extension(".ppt"), do: "PowerPoint"
  defp document_type_for_extension(".pptx"), do: "PowerPoint"
  defp document_type_for_extension(_), do: "Documento"

  @doc """
  Processa upload de documento usando pattern matching assertivo.
  Normaliza retornos em função privada conforme anti-padrões do Elixir.
  """
  @spec process_document_upload(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  defp process_document_upload(socket) do
    require Logger

    case socket.assigns.uploads.document.entries do
      [] ->
        Logger.debug("📄 Nenhum documento para upload")
        nil

      entries ->
        Logger.debug("📄 Processando upload de documento - #{length(entries)} entries")
        process_document_entries(socket, entries)
    end
  end

  # Normaliza processamento de documentos em função privada
  defp process_document_entries(socket, entries) do
    require Logger

    result = consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
      process_single_document_upload(path, entry)
    end)

    Logger.debug("📄 Resultado do consume_uploaded_entries: #{inspect(result)}")
    extract_document_url_from_result(result)
  end

  # Pattern matching assertivo para processamento de documento individual
  defp process_single_document_upload(path, entry) do
    require Logger

    filename = generate_unique_filename(entry.client_name)
    Logger.debug("📄 Upload de documento: #{entry.client_name} -> #{filename}")

    case App.Minio.upload_file(path, filename) do
      {:ok, url} ->
        Logger.info("✅ Documento enviado com sucesso: #{url}")
        {:ok, url}
      {:error, reason} ->
        Logger.error("❌ Falha no upload do documento: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  # Pattern matching assertivo para extração de URL
  defp extract_document_url_from_result(result) do
    case List.first(result) do
      url when is_binary(url) and url != "" and url != nil -> url
      {:ok, url} when is_binary(url) -> url
      _ -> nil
    end
  end

  @doc """
  Processa texto da mensagem para detectar links e extrair preview.
  Usa with para controle de fluxo assertivo conforme anti-padrões do Elixir.
  """
  @spec process_message_for_link_preview(String.t()) :: map() | nil
  defp process_message_for_link_preview(message_text) when is_binary(message_text) do
    with {:ok, link_data} <- App.LinkPreview.process_message_for_links(message_text),
         true <- not is_nil(link_data) do
      link_data
    else
      _ -> nil
    end
  end

  defp process_message_for_link_preview(_), do: nil

  @doc """
  Valida tipos de documento permitidos usando pattern matching assertivo.
  """
  @spec validate_document_type(String.t()) :: boolean()
  defp validate_document_type(filename) when is_binary(filename) do
    App.Minio.supported_file_type?(filename)
  end

  defp validate_document_type(_), do: false

  # Funções auxiliares privadas para validação seguindo anti-padrões do Elixir

  defp cancel_upload_by_ref(socket, ref) do
    case socket.assigns.uploads do
      %{image: %{entries: image_entries}, document: %{entries: document_entries}} ->
        cond do
          Enum.any?(image_entries, &(&1.ref == ref)) ->
            cancel_upload(socket, :image, ref)
          Enum.any?(document_entries, &(&1.ref == ref)) ->
            cancel_upload(socket, :document, ref)
          true ->
            socket
        end
      _ ->
        socket
    end
  end

  defp validate_image_entry(entry, socket) do
    if entry.valid? do
      {:noreply,
       socket
       |> assign(:message_error, nil)
       |> put_flash(:info, "Imagem selecionada: #{entry.client_name}")
      }
    else
      error_message = format_upload_error(entry.errors)
      {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  defp validate_document_entry(entry, socket) do
    cond do
      entry.valid? and validate_document_type(entry.client_name) ->
        document_type = get_document_type(entry.client_name)

        {:noreply,
         socket
         |> assign(:message_error, nil)
         |> put_flash(:info, "#{document_type} selecionado: #{entry.client_name}")
        }

      not entry.valid? ->
        error_message = format_document_upload_error(entry.errors)
        {:noreply, put_flash(socket, :error, error_message)}

      true ->
        {:noreply, put_flash(socket, :error, "Tipo de documento não suportado")}
    end
  end

  defp format_document_upload_error(errors) do
    Enum.map_join(errors, ", ", fn
      :too_large -> "Documento muito grande (máximo 25MB)"
      :not_accepted -> "Tipo de arquivo não aceito (apenas PDF, Word, Excel, PowerPoint)"
      :too_many_files -> "Apenas um documento por vez"
      :external_client_failure -> "Falha no upload"
      error -> "Erro: #{inspect(error)}"
    end)
  end

  defp validate_and_send_enhanced_message(
    %{text: trimmed_text, user_id: user_id, socket: socket},
    attachment_data,
    link_preview_data
  ) do
    case validate_enhanced_message_content(trimmed_text, socket, attachment_data.image_url, attachment_data.document_url) do
      :valid ->
        process_enhanced_message_sending(trimmed_text, socket, user_id, attachment_data, link_preview_data)
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp validate_enhanced_message_content(trimmed_text, _socket, image_url, document_url) do
    text_empty = is_nil(trimmed_text) or String.trim(trimmed_text || "") == ""
    has_image = not is_nil(image_url) and image_url != ""
    has_document = not is_nil(document_url) and document_url != ""
    has_attachment = has_image or has_document

    cond do
      text_empty and not has_attachment ->
        {:error, "Mensagem não pode estar vazia sem anexo"}

      not text_empty and String.length(trimmed_text) > ChatConfig.security_config()[:max_message_length] ->
        {:error, "Mensagem muito longa"}

      has_image and has_document ->
        {:error, "Envie apenas um tipo de anexo por vez"}

      true ->
        :valid
    end
  end

  defp process_enhanced_message_sending(trimmed_text, socket, user_id, attachment_data, link_preview_data) do
    case RateLimiter.check_message_rate(user_id, trimmed_text) do
      {:ok, :allowed} ->
        result = send_enhanced_chat_message(socket, trimmed_text, attachment_data, link_preview_data)
        if is_nil(socket.assigns[:message_error]) do
          RateLimiter.record_message(user_id, trimmed_text)
        end
        result

      {:error, reason, wait_time} ->
        error_message = format_rate_limit_error(reason, wait_time)
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  defp send_enhanced_chat_message(socket, text, attachment_data, link_preview_data) do
    message_type = determine_message_type(text, attachment_data.image_url, attachment_data.document_url)

    base_params = build_base_message_params(socket, text, message_type)
    enhanced_params = add_attachment_params(base_params, attachment_data, link_preview_data)

    case App.Chat.create_message(enhanced_params) do
      {:ok, message} ->
        handle_successful_message_creation(socket, message)
      {:error, changeset} ->
        handle_message_creation_error(socket, changeset)
    end
  end

  defp determine_message_type(text, image_url, document_url) do
    cond do
      not is_nil(image_url) and image_url != "" -> :imagem
      not is_nil(document_url) and document_url != "" -> :documento
      not is_nil(text) and text != "" -> :mensagem
      true -> :mensagem
    end
  end

  defp build_base_message_params(socket, text, message_type) do
    %{
      text: text || "",
      sender_id: socket.assigns.current_user_id,
      sender_name: socket.assigns.current_user_name,
      order_id: socket.assigns.order_id,
      tipo: message_type,
      status: :sent,
      reply_to: get_reply_to_id(socket),
      is_reply: not is_nil(socket.assigns[:replying_to])
    }
  end

  defp add_attachment_params(base_params, attachment_data, link_preview_data) do
    base_params
    |> add_image_params(attachment_data.image_url)
    |> add_document_params(attachment_data.document_url)
    |> add_link_preview_params(link_preview_data)
  end

  defp add_image_params(params, image_url) when is_binary(image_url) and image_url != "" do
    Map.put(params, :image_url, image_url)
  end
  defp add_image_params(params, _), do: params

  defp add_document_params(params, document_url) when is_binary(document_url) and document_url != "" do
    params
    |> Map.put(:document_url, document_url)
    |> Map.put(:document_name, extract_filename_from_url(document_url))
    |> Map.put(:document_size, nil)
  end
  defp add_document_params(params, _), do: params

  defp add_link_preview_params(params, %{title: title, description: desc, image: image, url: url}) do
    params
    |> Map.put(:link_preview_title, title)
    |> Map.put(:link_preview_description, desc)
    |> Map.put(:link_preview_image, image)
    |> Map.put(:link_preview_url, url)
  end
  defp add_link_preview_params(params, _), do: params

  defp get_reply_to_id(%{assigns: %{replying_to: %{id: id}}}), do: id
  defp get_reply_to_id(_), do: nil

  defp handle_successful_message_creation(socket, message) do
    topic = "order:#{socket.assigns.order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})

    {:noreply,
     socket
     |> assign(:message, "")
     |> assign(:replying_to, nil)
     |> assign(:message_error, nil)
     |> put_flash(:info, "Mensagem enviada com sucesso!")}
  end

  defp handle_message_creation_error(socket, changeset) do
    error_message = format_errors(changeset.errors)

    {:noreply,
     socket
     |> assign(:message_error, error_message)
     |> put_flash(:error, "Erro ao enviar mensagem: #{error_message}")}
  end

  defp format_rate_limit_error(reason, wait_time) do
    case reason do
      :rate_limited -> "Muitas mensagens. Aguarde #{wait_time} segundos."
      :duplicate_spam -> "Não repita a mesma mensagem. Aguarde #{wait_time} segundos."
      :long_message_spam -> "Muitas mensagens longas. Aguarde #{wait_time} segundos."
      _ -> "Rate limit atingido. Aguarde #{wait_time} segundos."
    end
  end

  defp extract_filename_from_url(url) when is_binary(url) do
    url |> String.split("/") |> List.last() || "documento"
  end
  defp extract_filename_from_url(_), do: "documento"
end
