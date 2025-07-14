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
  alias App.Chat.{MessageStatus, Notifications}
  alias AppWeb.Presence
  alias AppWeb.ChatLive.Helpers
  alias AppWeb.ChatLive.UploadHandler
  alias AppWeb.ChatLive.MessageHandler
  alias AppWeb.ChatLive.PresenceManager
  alias AppWeb.ChatLive.Components
  alias Phoenix.PubSub
  alias AppWeb.ChatLive.ThreadManager

  @type message_status :: :sent | :delivered | :read | :system
  @type message_type :: :mensagem | :imagem | :documento | :audio | :system_notification
  @type notification_type :: :join | :leave

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
  def mount(%{"order_id" => order_id} = _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, socket |> put_flash(:error, "Usuário não autenticado") |> push_navigate(to: "/auth/login")}

      _user ->
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
    image_url = UploadHandler.process_image_upload(socket)
    document_url = UploadHandler.process_document_upload(socket)

    attachments = MessageHandler.AttachmentData.new(image_url, document_url)
    trimmed_text = String.trim(text)

    link_preview_data = if trimmed_text != "", do: MessageHandler.process_message_for_link_preview(trimmed_text), else: nil

    request = MessageHandler.build_message_request(trimmed_text, socket, attachments, link_preview_data)
    MessageHandler.send_message(request)
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
    updated_socket = UploadHandler.cancel_upload_by_ref(socket, ref)
    {:noreply, updated_socket}
  end

  def handle_event("validate_image", _params, socket) do
    case socket.assigns.uploads.image.entries do
      [] ->
        {:noreply, socket}

      [entry | _] ->
        UploadHandler.validate_image_entry(entry, socket)
    end
  end

  @impl true
  def handle_event("validate_document", _params, socket) do
    case socket.assigns.uploads.document.entries do
      [] ->
        {:noreply, socket}

      [entry | _] ->
        UploadHandler.validate_document_entry(entry, socket)
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
    request = %AppWeb.ChatLive.ThreadManager.ThreadRequest{
      message_id: message_id,
      socket: socket,
      action: :reply
    }
    AppWeb.ChatLive.ThreadManager.handle_reply_to_message(request)
  end

  @impl true
  def handle_event("cancel_reply", _params, socket) do
    AppWeb.ChatLive.ThreadManager.handle_cancel_reply(socket)
  end

  @impl true
  def handle_event("show_thread", %{"message_id" => message_id}, socket) do
    request = %AppWeb.ChatLive.ThreadManager.ThreadRequest{
      message_id: message_id,
      socket: socket,
      action: :show
    }
    AppWeb.ChatLive.ThreadManager.handle_show_thread(request)
  end

  @impl true
  def handle_event("close_thread", _params, socket) do
    AppWeb.ChatLive.ThreadManager.handle_close_thread(socket)
  end

  @impl true
  def handle_event("update_thread_reply", %{"reply" => text}, socket) do
    AppWeb.ChatLive.ThreadManager.handle_update_thread_reply(text, socket)
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
    case UploadHandler.process_recorded_audio(socket, audio_params) do
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
    request = AppWeb.ChatLive.ThreadManager.ReplyRequest.new(text, socket)
    AppWeb.ChatLive.ThreadManager.handle_send_thread_reply(request)
  end

  @impl true
  def handle_event("jump_to_message", %{"message_id" => message_id}, socket) do
    AppWeb.ChatLive.ThreadManager.handle_jump_to_message(message_id, socket)
  end

  @impl true
  def handle_event("filter_by_tag", %{"tag" => tag}, socket) do
    filtered_messages = App.Chat.list_messages_by_tag(socket.assigns.order_id, tag)

    {:noreply,
      socket
      |> assign(:filtered_messages, filtered_messages)
      |> assign(:active_tag_filter, tag)
      |> assign(:has_more_messages, false)
    }
  end

  @impl true
  def handle_event("clear_tag_filter", _params, socket) do
    {:noreply,
      socket
      |> assign(:filtered_messages, socket.assigns.messages)
      |> assign(:active_tag_filter, nil)
      |> assign(:has_more_messages, true)
    }
  end

  @impl true
  def handle_info({:new_message, msg}, socket) do
    case {msg.order_id, socket.assigns.order_id} do
      {same_order, same_order} ->
        new_messages = socket.assigns.messages ++ [msg]
        user_id = socket.assigns.current_user_id

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
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:older_messages_loaded, older_messages, has_more}, socket) do
    new_messages = older_messages ++ socket.assigns.messages

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
    order_id = socket.assigns.order_id
    {:ok, messages, has_more} = App.Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit())

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
      users_online = PresenceManager.extract_unique_users_from_presences(presences)

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

    target_user_id = Map.get(notification, :target_user_id)
    current_user_id = socket.assigns.current_user_id


    if target_user_id && target_user_id == current_user_id do
      {:noreply, socket}
    else
      require Logger
      Logger.debug("Recebida notificação do sistema: #{inspect(Map.get(notification, :text, ""))}")


      system_notifications = socket.assigns.system_notifications ++ [notification]


      cutoff_time = DateTime.add(DateTime.utc_now(), -300, :second)
      fresh_notifications = Enum.filter(system_notifications, fn notif ->
        notification_time = Map.get(notif, :inserted_at, DateTime.utc_now())
        DateTime.compare(notification_time, cutoff_time) == :gt
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

    {:noreply, push_event(socket, "desktop-notification", notification_data)}
  end

  @impl true
  def handle_info({:status_update, message_id, user_id, status}, socket) do

    {:noreply, push_event(socket, "message-status-update", %{
      message_id: message_id,
      user_id: user_id,
      status: status
    })}
  end

  @impl true
  def handle_info({:bulk_read_update, user_id, count}, socket) do

    {:noreply, push_event(socket, "bulk-read-update", %{
      user_id: user_id,
      count: count
    })}
  end

  @impl true
  def handle_info({:message_read_notification, %{message_id: message_id, reader_id: reader_id}}, socket) do

    if socket.assigns.current_user_id != reader_id do
      Notifications.notify_message_read(socket.assigns.current_user_id, message_id, reader_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:bulk_read_notification, %{count: count, reader_id: reader_id, order_id: order_id}}, socket) do

    if socket.assigns.current_user_id != reader_id and socket.assigns.order_id == order_id do
      App.Chat.Notifications.notify_bulk_read(socket.assigns.current_user_id, order_id, count, reader_id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:mention_notification, %{message_id: message_id, mentioned_user: username} = notification}, socket) do

    if socket.assigns.current_user_name == username do

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
          <div class={Helpers.get_connection_indicator_class(@connected)} aria-hidden="true"></div>
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
              <span class={Helpers.get_status_class(@order["status"])}>
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
                  R$ {Helpers.format_currency(@order["amount"])}
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
                <dd class="font-semibold text-gray-900">{Helpers.format_date(@order["deliveryDate"])}</dd>
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
                    class={"w-8 h-8 md:w-10 md:h-10 rounded-full flex items-center justify-center mr-2 md:mr-3 shadow-md group-hover:shadow-lg transition-shadow duration-200 " <> Helpers.get_avatar_color(user, user)}
                    aria-hidden="true"
                  >
                    <span class="text-white text-xs md:text-sm font-bold">{Helpers.get_user_initial(user)}</span>
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
                <span class="text-white text-xs font-bold">{Helpers.get_user_initial(@current_user_name)}</span>
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold text-gray-900 truncate">{@current_user_name}</p>
                <p class="text-xs font-medium flex items-center">
                  <span class={Helpers.get_connection_indicator_class(@connected)} aria-hidden="true"></span>
                  <span class={Components.get_connection_text_class(@connected)}>{@connection_status}</span>
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
                  <div class={Helpers.get_connection_indicator_class(@connected)} aria-hidden="true"></div>
                  <span class="text-xs md:text-sm text-gray-600 font-medium">{@connection_status}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <div class={Helpers.get_connection_indicator_class(@connected)} aria-hidden="true"></div>
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
                    <%= Components.format_typing_users(@typing_users) %> digitando...
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
              <%= if Helpers.is_system_message?(msg) do %>
                <div class="flex justify-center my-3">
                  <div class="bg-gray-100 text-gray-600 text-sm px-4 py-2 rounded-full shadow-sm border">
                    <%= if Helpers.is_join_notification?(msg) do %>
                      <span class="text-green-600">●</span> <%= msg.text %>
                    <% else %>
                      <span class="text-gray-500">●</span> <%= msg.text %>
                    <% end %>
                                          <span class="text-xs text-gray-400 ml-2">
                        <%= Components.format_time(msg.inserted_at) %>
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
                  Components.get_message_color(msg.sender_id, @current_user_id, msg.sender_name)
                }>
                  <%= if msg.sender_id != @current_user_id do %>
                    <div class={"text-xs font-semibold mb-1 " <> Components.get_username_color(msg.sender_id, msg.sender_name)}>{msg.sender_name}</div>
                  <% end %>

                  <%= if Helpers.is_reply_message?(msg) do %>
                    <% original_preview = AppWeb.ChatLive.ThreadManager.build_original_message_preview(msg.reply_to, @messages) %>
                    <%= if original_preview do %>
                      <div class="bg-blue-50 border-l-4 border-blue-400 pl-3 pr-2 py-2 mb-3 rounded-r-lg">
                        <div class="flex items-start justify-between">
                          <div class="flex-1 min-w-0">
                            <div class="text-xs font-medium text-blue-700 mb-1">
                              Respondendo à <span class={"font-medium " <> Components.get_username_color(msg.reply_to, original_preview.sender_name)}>{original_preview.sender_name}</span>:
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

                  <%= if Helpers.is_audio_message?(msg) do %>
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
                        <%= Components.render_message_with_tags(msg) %>
                      </div>
                    <% end %>
                  <% end %>

                  <%= if Helpers.has_image?(msg) do %>
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
                  <%= if Helpers.has_document?(msg) do %>
                    <div class="document-preview mt-2 fade-in">
                      <div class="document-icon bg-blue-100">
                                                  <span class="text-xl">{Helpers.get_document_icon(msg.document_name || "documento")}</span>
                      </div>
                      <div class="document-info">
                        <div class="document-name">
                          {msg.document_name || "Documento"}
                        </div>
                                                  <div class="document-size">
                            {Helpers.get_document_type(msg.document_name || "")} •
                          <%= if msg.document_size do %>
                                                          {Components.format_file_size(msg.document_size)}
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
                  <%= if Helpers.has_link_preview?(msg) do %>
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

                      <% replies_count = Helpers.count_message_replies(msg.id, @messages) %>
                      <%= if replies_count do %>
                        <button
                          class="flex items-center space-x-1 text-xs text-gray-400 hover:text-purple-500 transition-colors px-2 py-1 rounded hover:bg-purple-50"
                          phx-click="show_thread"
                          phx-value-message_id={msg.id}
                          title="Ver conversa completa"
                        >
                          <span>Thread</span>
                                                      <span>{AppWeb.ChatLive.ThreadManager.format_thread_reply_counter(replies_count)}</span>
                        </button>
                      <% end %>

                      <%= if Helpers.is_original_message?(msg) do %>
                        <%= unless Helpers.count_message_replies(msg.id, @messages) do %>
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
                      <span class="text-xs text-gray-300">{Helpers.format_time(msg.inserted_at)}</span>
                      <%= if msg.sender_id == @current_user_id do %>
                        <div class="flex items-center space-x-1">
                                                      <%= case Helpers.get_message_status(msg) do %>
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
                          {Helpers.format_file_size(entry.client_size)} • {entry.client_type}
                        </p>
                        <%= if entry.valid? do %>
                          <p class="text-xs text-green-600">Pronto para envio</p>
                        <% else %>
                          <p class="text-xs text-red-600">✗ {Components.format_upload_error(entry.errors)}</p>
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
                          <span class="text-2xl">{Helpers.get_document_icon(entry.client_name)}</span>
                        </div>

                        <!-- Info do documento -->
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium text-gray-900 truncate">{entry.client_name}</p>
                          <p class="text-xs text-gray-500">
                            {Helpers.format_file_size(entry.client_size)} • {Helpers.get_document_type(entry.client_name)}
                          </p>
                          <%= if entry.valid? do %>
                            <p class="text-xs text-green-600">Pronto para envio</p>
                          <% else %>
                            <p class="text-xs text-red-600">✗ {Components.format_upload_error(entry.errors)}</p>
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
                                <div class={"w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 " <> Helpers.get_avatar_color(@thread_root_message.sender_id, @thread_root_message.sender_name)}>
                    <span class="text-white font-bold text-sm">{Helpers.get_user_initial(@thread_root_message.sender_name)}</span>
              </div>
              <div class="flex-1 min-w-0">
                                 <div class="flex items-center space-x-2 mb-2">
                   <span class={"font-semibold " <> Components.get_username_color(@thread_root_message.sender_id, @thread_root_message.sender_name)}>{@thread_root_message.sender_name}</span>
                  <span class="text-xs text-gray-500">{Components.format_time(@thread_root_message.inserted_at)}</span>
                  <span class="bg-purple-100 text-purple-800 text-xs px-2 py-1 rounded-full font-medium">Mensagem Original</span>
                </div>
                <%= unless @thread_root_message.tipo == "imagem" and @thread_root_message.text == "Imagem enviada" do %>
                  <div class="text-gray-800 leading-relaxed">
                    <%= if Helpers.has_mentions?(@thread_root_message) do %>
                      {Components.render_message_with_mention_highlights(@thread_root_message.text)}
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
                                       <div class={"w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 " <> Helpers.get_avatar_color(reply.sender_id, reply.sender_name)}>
                      <span class="text-white font-bold text-xs">{Helpers.get_user_initial(reply.sender_name)}</span>
                   </div>
                  <div class="flex-1 min-w-0">
                                         <div class="flex items-center space-x-2 mb-1">
                       <span class={"font-medium " <> Components.get_username_color(reply.sender_id, reply.sender_name)}>{reply.sender_name}</span>
                      <span class="text-xs text-gray-500">{Components.format_time(reply.inserted_at)}</span>
                      <span class="bg-blue-100 text-blue-800 text-xs px-2 py-1 rounded-full">#{index + 1}</span>
                    </div>
                    <div class={
                      "p-3 rounded-xl " <>
                      AppWeb.ChatLive.ThreadManager.get_thread_reply_color(reply.sender_id, @current_user_id, reply.sender_name)
                    }>
                      <%= unless reply.tipo == "imagem" and reply.text == "Imagem enviada" do %>
                        <%= if Helpers.has_mentions?(reply) do %>
                          {Components.render_message_with_mention_highlights(reply.text)}
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
                                        <span class="text-white font-bold text-xs">{Helpers.get_user_initial(@current_user_name)}</span>
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











  defp initialize_chat_socket(socket, order_id) do
    topic = "order:#{order_id}"

    config = PresenceManager.build_presence_config(socket, topic, order_id)
    PresenceManager.setup_presence_if_connected(config)
    order = load_order_data(order_id)
    {messages, has_more} = load_messages(order_id)

    setup_socket_assigns(socket, order_id, topic, order, messages, has_more)
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
        PresenceManager.extract_unique_users_from_presences(presences)
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



  defp load_older_messages_async(socket) do
    order_id = socket.assigns.order_id
    _current_count = length(socket.assigns.messages)

    Task.start(fn ->
      case App.Chat.list_messages_for_order(order_id, ChatConfig.pagination_config()[:default_limit]) do
        {:ok, older_messages, has_more} ->
          send(self(), {:older_messages_loaded, older_messages, has_more})
      end
    end)

    socket
  end












  defp process_presence_notifications(diff, topic, current_user_id) do
    change = %PresenceManager.PresenceChange{
      joins: Map.get(diff, :joins, %{}),
      leaves: Map.get(diff, :leaves, %{}),
      topic: topic,
      socket: %{assigns: %{current_user_id: current_user_id}}
    }

    PresenceManager.process_presence_change(change)
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


  defp get_all_messages_with_notifications(messages, system_notifications) do
    # Combinar e ordenar por timestamp
    all_items = messages ++ system_notifications

    Enum.sort(all_items, fn a, b ->
      DateTime.compare(a.inserted_at, b.inserted_at) != :gt
    end)
  end
end
