defmodule AppWeb.ChatLive do
  @moduledoc """
  LiveView component for real-time chat functionality in order management.

  Provides secure chat interface for order discussions with features like:
  - Real-time messaging with PubSub
  - User presence tracking
  - File upload support
  - Tag management for orders
  - Message history with pagination
  """
  use AppWeb, :live_view
  alias AppWeb.Presence
  alias App.ChatConfig
  alias App.Tags
  alias App.DateTimeHelper
  require Logger

  @doc """
  Authentication hook that validates user session tokens.

  Ensures secure access by verifying Guardian tokens from session data
  before allowing chat participation. Anonymous users are permitted
  but with limited functionality.
  """
  def on_mount(:default, _params, session, socket) do
    Logger.info("on_mount: session user_token = #{inspect(session["user_token"])}")

    case session["user_token"] do
      nil ->
        Logger.info("on_mount: No token found")
        {:cont, socket}

      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            Logger.info("on_mount: Authenticated user: #{user.name || user.username}")
            {:cont, assign(socket, :current_user, user)}

          {:error, reason} ->
            Logger.error("on_mount: Token decode error: #{inspect(reason)}")
            {:cont, socket}
        end
    end
  end

  @doc """
  Initializes the chat LiveView for a specific order.

  Sets up real-time subscriptions, loads order data and message history,
  and configures user presence tracking. Handles both authenticated and
  anonymous users with appropriate permission levels.
  """
  @impl true
  def mount(%{"order_id" => order_id} = _params, session, socket) do
    topic = "order:#{order_id}"

    Logger.info("Socket assigns current_user: #{inspect(socket.assigns[:current_user])}")
    Logger.info("Session user_token: #{inspect(session["user_token"])}")

    {current_user_name, authenticated_user} = resolve_user_identity(socket, session)

    if connected?(socket) do
      setup_pubsub_subscriptions(topic, authenticated_user)
      setup_presence_tracking(topic, socket, current_user_name, authenticated_user, order_id)
      schedule_connection_status_update()
    end

    order_data = fetch_order_with_fallback(order_id)
    {message_history, has_more_messages} = load_paginated_messages(order_id)
    order_tags = Tags.get_order_tags(order_id)
    current_presences = Presence.list(topic)
    online_users = extract_users_from_presences(current_presences)

    if authenticated_user do
      App.Accounts.record_order_access(authenticated_user.id, order_id)
    end

    socket = assign_initial_socket_data(socket, %{
      order_id: order_id,
      order: order_data,
      messages: message_history,
      has_more_messages: has_more_messages,
      order_tags: order_tags,
      presences: current_presences,
      users_online: online_users,
      current_user: current_user_name,
      user_object: authenticated_user,
      token: session["user_token"],
      topic: topic
    })

    {:ok, socket}
  end

  # --- User Authentication & Identity ---

  defp resolve_user_identity(socket, session) do
    case socket.assigns[:current_user] do
      nil -> extract_user_from_session_token(session)
      user -> extract_user_from_socket_assigns(user)
    end
  end

  defp extract_user_from_session_token(session) do
    token = session["user_token"]
    case token do
      nil ->
        Logger.info("No token found in session")
        {ChatConfig.default_username(), nil}
      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            Logger.info("User found via token: #{user.name || user.username}")
            {user.name || user.username || ChatConfig.default_username(), user}
          {:error, reason} ->
            Logger.error("Token decode error: #{inspect(reason)}")
            {ChatConfig.default_username(), nil}
        end
    end
  end

  defp extract_user_from_socket_assigns(user) do
    user_name = user.name || user.username || ChatConfig.default_username()
    Logger.info("User authenticated via on_mount: #{user_name} (ID: #{user.id})")
    {user_name, user}
  end

  # --- Real-time Communication Setup ---

  defp setup_pubsub_subscriptions(topic, authenticated_user) do
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    if authenticated_user do
      Phoenix.PubSub.subscribe(App.PubSub, "user:#{authenticated_user.id}")
    end
  end

  defp setup_presence_tracking(topic, socket, user_name, authenticated_user, order_id) do
    user_data = %{
      user_id: case authenticated_user do
        nil -> "anonymous"
        user -> user.id
      end,
      name: user_name,
      joined_at: DateTimeHelper.now() |> DateTime.to_iso8601(),
      user_agent: get_connect_info(socket, :user_agent) || "Unknown"
    }

    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
        Logger.info("User #{user_name} joined chat for order #{order_id}")
        # Also track in active rooms system
        if authenticated_user do
          case Process.whereis(App.ActiveRooms) do
            nil ->
              Logger.warning("ActiveRooms GenServer not available")
            _pid ->
              try do
                App.ActiveRooms.join_room(order_id, authenticated_user.id, user_name)
              rescue
                e -> Logger.error("Failed to join active room: #{inspect(e)}")
              catch
                :exit, reason -> Logger.error("ActiveRooms process not available: #{inspect(reason)}")
              end
          end
        end
      {:error, reason} -> Logger.error("Failed to track presence: #{inspect(reason)}")
    end
  end

  defp schedule_connection_status_update do
    Process.send_after(self(), :update_connection_status, 5000)
  end

  # --- Data Loading & Management ---

  defp fetch_order_with_fallback(order_id) when is_binary(order_id) do
    case App.Orders.get_order(order_id) do
      {:ok, order} -> order
      {:error, _} ->
        %{
          "orderId" => order_id,
          "status" => "Não encontrado",
          "customerName" => "N/A",
          "amount" => "0",
          "deliveryType" => "N/A",
          "deliveryDate" => ""
        }
    end
  end

  defp load_paginated_messages(order_id) when is_binary(order_id) do
    case App.Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit()) do
      {:ok, messages, has_more} -> {messages, has_more}
      {:error, _reason} -> {[], false}
    end
  end

  defp format_message_with_mentions(text) when is_binary(text) do
    # Replace @username with highlighted mentions
    text
    |> String.replace(~r/@(\w+)/, ~s(<span class="bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded-md text-xs font-medium">@\\1</span>))
    |> Phoenix.HTML.raw()
  end
  defp format_message_with_mentions(_), do: ""

  defp assign_initial_socket_data(socket, data) do
    socket
    |> assign(:order_id, data.order_id)
    |> assign(:order, data.order)
    |> assign(:messages, data.messages)
    |> assign(:has_more_messages, data.has_more_messages)
    |> assign(:order_tags, data.order_tags)
    |> assign(:presences, data.presences)
    |> assign(:message, "")
    |> assign(:users_online, data.users_online)
    |> assign(:current_user, data.current_user)
    |> assign(:user_object, data.user_object)
    |> assign(:token, data.token)
    |> assign(:connected, connected?(socket))
    |> assign(:connection_status, if(connected?(socket), do: "Conectado", else: "Desconectado"))
    |> assign(:topic, data.topic)
    |> assign(:loading_messages, false)
    |> assign(:message_error, nil)
    |> assign(:modal_image_url, nil)
    |> assign(:typing_users, [])
    |> assign(:show_typing_indicator, false)
    |> assign(:show_search, false)
    |> assign(:message_count, length(data.messages))
    |> assign(:show_tag_modal, false)
    |> assign(:tag_search_query, "")
    |> assign(:tag_search_results, [])
    |> assign(:show_sidebar, false)
    |> allow_upload(:image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1, max_file_size: 5_000_000)
  end

  # --- Message Processing ---

  @doc """
  Processes message sending with validation and security checks.

  Validates message content, handles image uploads, and broadcasts
  the message to all connected users in the order chat room.
  """
  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    trimmed_text = String.trim(text)

    case validate_message_input(socket, trimmed_text) do
      {:error, error_msg} ->
        {:noreply, put_flash(socket, :error, error_msg)}

      {:ok, _} ->
        process_message_send(socket, trimmed_text)
    end
  end

  defp validate_message_input(socket, trimmed_text) do
    cond do
      trimmed_text == "" && Enum.empty?(socket.assigns.uploads.image.entries) ->
        {:error, "Mensagem não pode estar vazia"}

      String.length(trimmed_text) > ChatConfig.security_config()[:max_message_length] ->
        {:error, "Mensagem muito longa"}

      not connected?(socket) ->
        {:error, "Conexão perdida. Tente recarregar a página."}

      true ->
        {:ok, :valid}
    end
  end

  defp process_message_send(socket, trimmed_text) do
    image_url = process_image_upload(socket)
    {user_id, user_name} = extract_user_info_for_message(socket)

    case App.Chat.send_message(socket.assigns.order_id, user_id, trimmed_text, image_url) do
      {:ok, _message} ->
        Logger.info("Message sent by #{user_name} in order #{socket.assigns.order_id}")
        {:noreply,
          socket
          |> assign(:message, "")
          |> assign(:message_error, nil)
        }
      {:error, changeset} ->
        Logger.error("Failed to send message: #{inspect(changeset.errors)}")
        {:noreply, assign(socket, :message_error, "Erro ao enviar mensagem")}
    end
  end

  defp process_image_upload(socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path, client_name: name}, _entry ->
      filename = "#{UUID.uuid4()}_#{name}"
      case App.Minio.upload_file(path, filename) do
        {:ok, url} -> url
        _ -> nil
      end
    end)
    |> List.first()
  end

  defp extract_user_info_for_message(socket) do
    case socket.assigns[:user_object] do
      nil -> {nil, socket.assigns.current_user}
      user -> {user.id, user.name || user.username}
    end
  end

  @doc """
  Loads additional message history for the current order.

  Implements pagination to prevent overwhelming the client with
  large message histories while maintaining responsive UX.
  """
  @impl true
  def handle_event("load_older_messages", _params, socket) do
    if socket.assigns.loading_messages do
      {:noreply, socket}
    else
      {:noreply,
        socket
        |> assign(:loading_messages, true)
        |> load_older_messages_async()
      }
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :message_error, nil)}
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    if connected?(socket) && String.length(message) > 0 do
      Phoenix.PubSub.broadcast(App.PubSub, socket.assigns.topic, {:typing_start, socket.assigns.current_user})
    end

    {:noreply, assign(socket, :message, message)}
  end

    @impl true
  def handle_event("stop_typing", _params, socket) do
    if connected?(socket) do
      Phoenix.PubSub.broadcast(App.PubSub, socket.assigns.topic, {:typing_stop, socket.assigns.current_user})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_search", _params, socket) do
    {:noreply, assign(socket, :show_search, !socket.assigns[:show_search])}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_sidebar, !socket.assigns[:show_sidebar])}
  end

  # These events may come from order_search_live component - we ignore them here to prevent conflicts
  def handle_event("focus_search", _params, socket), do: {:noreply, socket}
  def handle_event("blur_search", _params, socket), do: {:noreply, socket}
  def handle_event("stopPropagation", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("exit_chat", _params, socket) do
    # Navegar de volta para a tela de busca de pedidos
    {:noreply, push_navigate(socket, to: "/buscar-pedido")}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    filtered_messages = socket.assigns.messages
    |> Enum.filter(fn message ->
      String.contains?(String.downcase(message.text), String.downcase(query))
    end)

    {:noreply, assign(socket, :filtered_messages, filtered_messages)}
  end

  @impl true
  def handle_event("search_users", %{"query" => query}, socket) do
    matching_users = socket.assigns.users_online
    |> Enum.filter(fn username ->
      String.contains?(String.downcase(username), String.downcase(query))
    end)
    |> Enum.take(5) # Limit results to prevent UI overflow

    Logger.info("Search users query: '#{query}', found: #{inspect(matching_users)}")
    Logger.info("All users online: #{inspect(socket.assigns.users_online)}")

    {:noreply,
      socket
      |> push_event("show-user-suggestions", %{
        users: matching_users,
        query: query
      })
    }
  end



  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
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
  def handle_event("show_tag_modal", _params, socket) do
    require Logger
    Logger.info("show_tag_modal event triggered")
    Logger.info("User object: #{inspect(socket.assigns.user_object)}")
    Logger.info("Store ID: #{inspect(socket.assigns.user_object.store_id)}")

    all_tags = Tags.list_tags(socket.assigns.user_object.store_id)
    Logger.info("Tags found: #{length(all_tags)}")

    {:noreply,
      socket
      |> assign(:show_tag_modal, true)
      |> assign(:tag_search_results, all_tags)
      |> assign(:tag_search_query, "")
    }
  end

  @impl true
  def handle_event("hide_tag_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:show_tag_modal, false)
      |> assign(:tag_search_query, "")
      |> assign(:tag_search_results, [])
    }
  end

    @impl true
  def handle_event("search_tags", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = Tags.search_tags(query, socket.assigns.user_object.store_id)
      {:noreply,
        socket
        |> assign(:tag_search_query, query)
        |> assign(:tag_search_results, results)
      }
    else
      {:noreply,
        socket
        |> assign(:tag_search_query, query)
        |> assign(:tag_search_results, [])
      }
    end
  end

  @impl true
  def handle_event("search_tags", %{"value" => query}, socket) do
    if String.length(query) >= 2 do
      results = Tags.search_tags(query, socket.assigns.user_object.store_id)
      {:noreply,
        socket
        |> assign(:tag_search_query, query)
        |> assign(:tag_search_results, results)
      }
    else
      # Show all tags when query is too short to give users context of available options
      all_tags = Tags.list_tags(socket.assigns.user_object.store_id)
      {:noreply,
        socket
        |> assign(:tag_search_query, query)
        |> assign(:tag_search_results, all_tags)
      }
    end
  end

  @impl true
  def handle_event("add_tag_to_order", %{"tag_id" => tag_id}, socket) do
    user_id = socket.assigns.user_object.id

          case Tags.add_tag_to_order(socket.assigns.order_id, tag_id, user_id) do
        {:ok, _order_tag} ->
          order_tags = Tags.get_order_tags(socket.assigns.order_id)
          {:noreply,
            socket
            |> assign(:order_tags, order_tags)
            |> assign(:show_tag_modal, false)
            |> assign(:tag_search_query, "")
            |> assign(:tag_search_results, [])
            |> put_flash(:info, "Tag adicionada com sucesso!")
          }
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Erro ao adicionar tag")}
    end
  end

  @impl true
  def handle_event("remove_tag_from_order", %{"tag_id" => tag_id}, socket) do
    case Tags.remove_tag_from_order(socket.assigns.order_id, tag_id) do
      {count, nil} when count > 0 ->
        order_tags = Tags.get_order_tags(socket.assigns.order_id)
        {:noreply,
          socket
          |> assign(:order_tags, order_tags)
          |> put_flash(:info, "Tag removida com sucesso!")
        }
      _ ->
        {:noreply, put_flash(socket, :error, "Erro ao remover tag")}
    end
  end

  @doc """
  Handles incoming messages from PubSub and updates the UI.

  Filters messages for the current order and provides visual/audio
  notifications for messages from other users to enhance real-time collaboration.
  """
  @impl true
  def handle_info({:new_message, msg}, socket) do
    if msg.order_id == socket.assigns.order_id do
      socket = socket
      |> update(:messages, fn current_messages -> current_messages ++ [msg] end)
      |> update(:message_count, fn count -> count + 1 end)
      |> push_event("scroll-to-bottom", %{})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:notification, :new_message, notification_data}, socket) do
    {:noreply,
      socket
      |> push_event("show-notification", %{
        title: "Nova mensagem",
        body: "#{notification_data.sender_name}: #{String.slice(notification_data.text, 0, 50)}",
        icon: "/images/notification-icon.svg",
        data: %{
          order_id: notification_data.order_id,
          message_id: notification_data.message.id
        }
      })
    }
  end

  @impl true
  def handle_info({:notification, :mention, notification_data}, socket) do
    {:noreply,
      socket
      |> push_event("show-notification", %{
        title: "Você foi mencionado!",
        body: "#{notification_data.sender_name} mencionou você: #{String.slice(notification_data.text, 0, 50)}",
        icon: "/images/notification-icon.svg",
        data: %{
          order_id: notification_data.order_id,
          message_id: notification_data.message.id
        }
      })
      |> push_event("play-notification-sound", %{})
    }
  end

  @impl true
  def handle_info({:desktop_notification, notification_data}, socket) do
    {:noreply,
      socket
      |> push_event("show-desktop-notification", notification_data)
    }
  end

  @impl true
  def handle_info({:typing_start, user}, socket) do
    if user != socket.assigns.current_user do
      {:noreply,
        socket
        |> update(:typing_users, fn users -> [user | users] |> Enum.uniq() end)
        |> assign(:show_typing_indicator, true)
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:typing_stop, user}, socket) do
    updated_socket = socket
    |> update(:typing_users, fn users -> List.delete(users, user) end)

    {:noreply,
      updated_socket
      |> assign(:show_typing_indicator, length(updated_socket.assigns.typing_users) > 1)
    }
  end

  @impl true
  def handle_info({:older_messages_loaded, older_messages, has_more}, socket) do
    {:noreply,
      socket
      |> assign(:messages, older_messages ++ socket.assigns.messages)
      |> assign(:has_more_messages, has_more)
      |> assign(:loading_messages, false)
    }
  end

  @doc """
  Updates user presence information when users join or leave the chat.

  Maintains real-time visibility of active participants to improve
  collaboration awareness and communication context.
  """
  @impl true
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    presences = Presence.list(socket.assigns.topic)
    users_online = extract_users_from_presences(presences)



    {:noreply,
      socket
      |> assign(:presences, presences)
      |> assign(:users_online, users_online)
    }
  end

  @impl true
  def handle_info(:update_connection_status, socket) do
    is_connected = connected?(socket)
    connection_status = if(is_connected, do: "Conectado", else: "Desconectado")

    # Remove user from active rooms when disconnected
    if not is_connected and socket.assigns.user_object do
      case Process.whereis(App.ActiveRooms) do
        nil -> :ok
        _pid ->
          try do
            App.ActiveRooms.leave_room(socket.assigns.order_id, socket.assigns.user_object.id)
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
      end
    end

    # Continue monitoring while connected to provide real-time status updates
    if is_connected do
      Process.send_after(self(), :update_connection_status, 5000)
    end

    {:noreply,
      socket
      |> assign(:connected, is_connected)
      |> assign(:connection_status, connection_status)
      |> push_event("connection-status", %{connected: is_connected, status: connection_status})
    }
  end

  @impl true
  def terminate(_reason, socket) do
    # Remove user from active rooms when LiveView terminates
    if socket.assigns.user_object do
      case Process.whereis(App.ActiveRooms) do
        nil -> :ok
        _pid ->
          try do
            App.ActiveRooms.leave_room(socket.assigns.order_id, socket.assigns.user_object.id)
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
      end
    end
    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chat-container"
         class="min-h-screen w-full bg-slate-50 font-sans antialiased flex flex-col md:flex-row overflow-hidden m-0 p-0 relative"
         phx-hook="ChatHook"
         role="main">

      <!-- Sidebar -->
      <aside class={"fixed md:relative inset-y-0 left-0 w-full md:w-96 bg-white border-r border-slate-200 flex flex-col shadow-2xl z-30 flex-shrink-0 m-0 p-0 transition-transform duration-300 ease-in-out " <>
                   if(@show_sidebar, do: "translate-x-0", else: "-translate-x-full md:translate-x-0")}
             role="complementary"
             aria-label="Informações do pedido e usuários online">
         <header class="p-4 md:p-6 border-b border-slate-100 bg-gradient-to-r from-slate-800 via-slate-900 to-slate-800">
           <div class="flex items-center justify-between">
             <div class="flex items-center space-x-2 md:space-x-3">
               <div class="w-10 h-10 md:w-12 md:h-12 bg-gradient-to-br from-slate-600 to-slate-800 rounded-2xl flex items-center justify-center shadow-xl">
                 <svg class="w-6 h-6 md:w-7 md:h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path></svg>
               </div>
               <div>
                 <h1 class="text-lg md:text-2xl font-bold text-white tracking-tight">JuruConnect</h1>
               </div>
             </div>
             <!-- Botão para fechar sidebar no mobile -->
             <button phx-click="toggle_sidebar" class="md:hidden p-2 text-white/80 hover:text-white hover:bg-white/10 rounded-lg transition-all duration-200" aria-label="Fechar informações do pedido">
               <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
               </svg>
             </button>
           </div>
         </header>

        <!-- Pedido Info Card -->
        <section class="p-4 md:p-6" aria-labelledby="order-info-title">
          <h2 id="order-info-title" class="sr-only">Informações do Pedido</h2>
          <div class="bg-gradient-to-br from-slate-50 via-white to-slate-50 rounded-2xl p-3 md:p-6 border border-slate-200 shadow-lg hover:shadow-xl transition-all duration-300">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center space-x-2">
                <svg class="w-5 h-5 text-slate-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                </svg>
                <h3 class="text-lg md:text-xl font-bold text-gray-900">
                  Pedido #<%= @order["orderId"] %>
                </h3>
              </div>
              <span class={get_status_class(@order["status"])}>
                <%= @order["status"] %>
              </span>
            </div>

            <dl class="space-y-3 md:space-y-4 text-sm">
              <div class="flex justify-between items-center py-2 border-b border-slate-100">
                <dt class="text-slate-600 font-semibold flex items-center text-xs md:text-sm">
                  <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"></path>
                  </svg>
                  Cliente:
                </dt>
                <dd class="font-bold text-slate-900 truncate ml-2 max-w-24 md:max-w-32 text-xs md:text-sm" title={@order["customerName"]}>
                  <%= @order["customerName"] %>
                </dd>
              </div>
              <div class="flex justify-between items-center py-2 border-b border-slate-100">
                <dt class="text-slate-600 font-semibold flex items-center text-xs md:text-sm">
                  <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1"></path>
                  </svg>
                  Valor:
                </dt>
                <dd class="font-bold text-emerald-700 text-sm md:text-lg">R$ <%= format_currency(@order["amount"]) %></dd>
              </div>
              <div class="flex justify-between items-center py-2 border-b border-slate-100">
                <dt class="text-slate-600 font-semibold flex items-center text-xs md:text-sm">
                  <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"></path>
                  </svg>
                  Entrega:
                </dt>
                <dd class="font-bold text-slate-900 text-xs md:text-sm"><%= @order["deliveryType"] %></dd>
              </div>
              <div class="flex justify-between items-center py-2 border-b border-slate-100">
                <dt class="text-slate-600 font-semibold flex items-center text-xs md:text-sm">
                  <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c1.1 0 2 .9 2 2v5.293l2.646-2.647a.5.5 0 01.708.708l-3.5 3.5a.5.5 0 01-.708 0L7 10.207V7z"></path>
                  </svg>
                  Tipo:
                </dt>
                <dd class="font-bold text-slate-900 text-xs md:text-sm"><%= @order["orderType"] || "N/A" %></dd>
              </div>
              <div class="flex justify-between items-center py-2">
                <dt class="text-slate-600 font-semibold flex items-center text-xs md:text-sm">
                  <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3a2 2 0 012-2h4a2 2 0 012 2v4m-6 4v10a2 2 0 002 2h4a2 2 0 002-2V11m-6 0h6"></path>
                  </svg>
                  Data:
                </dt>
                <dd class="font-bold text-slate-900 text-xs md:text-sm"><%= format_date(@order["deliveryDate"]) %></dd>
              </div>
            </dl>
          </div>

          <!-- Seção de Tags - Melhorada para maior visibilidade -->
          <div class="mt-4 md:mt-6">
            <div class="flex items-center justify-between mb-3 md:mb-4">
              <h4 class="text-xs md:text-sm font-bold text-slate-800 flex items-center">
                <svg class="w-4 h-4 md:w-5 md:h-5 mr-1 md:mr-2 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="7 7h.01M7 3h5c1.1 0 2 .9 2 2v5.293l2.646-2.647a.5.5 0 01.708.708l-3.5 3.5a.5.5 0 01-.708 0L7 10.207V7z"></path>
                </svg>
                Status do Pedido
              </h4>
              <button phx-click="show_tag_modal"
                      class="p-1.5 md:p-2 text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-lg transition-all duration-200 border border-slate-200 hover:border-slate-300"
                      title="Gerenciar status">
                <svg class="w-3 h-3 md:w-4 md:h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                </svg>
              </button>
            </div>

            <div class="space-y-2 md:space-y-3">
              <%= if Enum.empty?(@order_tags) do %>
                <div class="bg-slate-50 border-2 border-dashed border-slate-200 rounded-lg p-3 md:p-4 text-center">
                  <svg class="w-6 h-6 md:w-8 md:h-8 text-slate-400 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="7 7h.01M7 3h5c1.1 0 2 .9 2 2v5.293l2.646-2.647a.5.5 0 01.708.708l-3.5 3.5a.5.5 0 01-.708 0L7 10.207V7z"></path>
                  </svg>
                  <p class="text-xs md:text-sm text-slate-500 font-medium">Nenhum status definido</p>
                  <p class="text-xs text-slate-400 mt-1">Clique no botão + para adicionar um status</p>
                </div>
              <% else %>
                <%= for tag <- @order_tags do %>
                  <div class="flex items-center justify-between bg-white border-2 border-slate-200 rounded-xl px-3 md:px-4 py-2 md:py-3 shadow-sm hover:shadow-md transition-all duration-200 group">
                    <div class="flex items-center">
                      <div class="w-3 h-3 md:w-4 md:h-4 rounded-full mr-2 md:mr-3 shadow-sm" style={"background-color: #{tag.color}"}></div>
                      <div>
                        <span class="text-xs md:text-sm font-bold text-slate-800"><%= tag.name %></span>
                        <%= if tag.description do %>
                          <p class="text-xs text-slate-500 mt-0.5 hidden md:block"><%= tag.description %></p>
                        <% end %>
                      </div>
                    </div>
                    <button phx-click="remove_tag_from_order"
                            phx-value-tag_id={tag.id}
                            class="p-1 md:p-1.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-all duration-200 opacity-0 group-hover:opacity-100"
                            title="Remover status">
                      <svg class="w-3 h-3 md:w-4 md:h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                      </svg>
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </section>

        <!-- Usuários Online -->
        <section class="px-4 md:px-6 mb-4 md:mb-6 flex-1" aria-labelledby="users-online-title">
          <h2 id="users-online-title" class="text-xs md:text-sm font-bold text-slate-800 mb-3 md:mb-4 flex items-center">
            <div class="w-2 h-2 md:w-2.5 md:h-2.5 bg-emerald-500 rounded-full mr-2 md:mr-3 animate-pulse shadow-sm" aria-hidden="true"></div>
            <svg class="w-3 h-3 md:w-4 md:h-4 mr-1 md:mr-2 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
            </svg>
            Usuários Online (<%= length(@users_online) %>)
          </h2>

          <div class="space-y-1 md:space-y-2 max-h-48 md:max-h-64 overflow-y-auto" role="list">
            <%= if Enum.empty?(@users_online) do %>
              <div class="text-center py-6 md:py-8">
                <svg class="w-8 h-8 md:w-12 md:h-12 text-slate-300 mx-auto mb-2 md:mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
                </svg>
                <p class="text-xs md:text-sm text-slate-500 italic">Nenhum usuário online</p>
              </div>
            <% else %>
              <%= for user <- @users_online do %>
                <div class="flex items-center p-2 md:p-3 rounded-xl hover:bg-slate-50 transition-all duration-200 border border-transparent hover:border-slate-200 hover:shadow-sm group" role="listitem">
                  <div class="w-8 h-8 md:w-10 md:h-10 bg-gradient-to-br from-slate-600 to-slate-800 rounded-full flex items-center justify-center mr-2 md:mr-3 shadow-md group-hover:shadow-lg transition-shadow duration-200" aria-hidden="true">
                    <span class="text-white text-xs md:text-sm font-bold"><%= get_user_initial(user) %></span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <span class="text-xs md:text-sm font-semibold text-slate-800 truncate block"><%= user %></span>
                    <%= if user == @current_user do %>
                      <span class="text-xs text-slate-700 font-medium">(Você)</span>
                    <% end %>
                  </div>
                  <div class="w-1.5 h-1.5 md:w-2 md:h-2 bg-emerald-400 rounded-full flex-shrink-0 animate-pulse" aria-label="Online" title="Online"></div>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>

         <!-- Footer com informações do usuário atual -->
         <footer class="p-3 md:p-6 border-t border-slate-100 bg-slate-50/50">
           <div class="flex items-center justify-between">
             <div class="flex items-center flex-1 min-w-0">
               <div class="w-8 h-8 md:w-10 md:h-10 bg-gradient-to-br from-slate-600 to-slate-800 rounded-full flex items-center justify-center mr-2 md:mr-3 shadow-md" aria-hidden="true">
                 <span class="text-white text-xs md:text-sm font-bold"><%= get_user_initial(@current_user) %></span>
               </div>
               <div class="min-w-0 flex-1">
                 <p class="text-xs md:text-sm font-semibold text-slate-900 truncate"><%= @current_user %></p>
                 <p class="text-xs font-medium flex items-center">
                   <span class={get_connection_indicator_class(@connected)} aria-hidden="true"></span>
                   <span class={get_connection_text_class(@connected)}><%= @connection_status %></span>
                 </p>
               </div>
             </div>
             <div class="flex items-center space-x-1 md:space-x-2">
               <button class="p-1.5 md:p-2.5 text-slate-500 hover:text-slate-700 hover:bg-slate-100 transition-all duration-200 rounded-lg hover:shadow-sm"
                       aria-label="Configurações"
                       title="Configurações">
                 <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                 </svg>
               </button>
               <button
                 phx-click="exit_chat"
                 class="p-1.5 md:p-2.5 text-slate-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm"
                 title="Sair do chat e voltar para busca de pedidos"
                 aria-label="Sair do chat"
               >
                 <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                   <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path>
                 </svg>
               </button>
             </div>
           </div>
         </footer>
      </aside>

      <!-- Área principal do chat - colada na sidebar -->
      <main class="flex-1 h-full md:h-screen flex flex-col bg-white min-w-0 border-t md:border-l border-slate-200 max-w-none m-0 p-0 md:ml-0" role="main" aria-label="Área de chat">
        <!-- Header do Chat -->
        <header class="flex flex-col md:flex-row items-start md:items-center justify-between p-3 md:p-6 border-b border-slate-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-lg">
          <div class="flex items-center w-full">
            <!-- Botão para abrir sidebar no mobile -->
            <button phx-click="toggle_sidebar" class="md:hidden p-2 text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-lg transition-all duration-200 mr-2 flex-shrink-0" aria-label="Abrir informações do pedido">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
              </svg>
            </button>
            <div class="flex items-center space-x-2 md:space-x-3 flex-1 min-w-0">
              <div class="w-10 h-10 md:w-12 md:h-12 bg-gradient-to-br from-slate-700 to-slate-900 rounded-2xl flex items-center justify-center shadow-xl">
                <svg class="w-6 h-6 md:w-7 md:h-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex flex-col space-y-1">
                  <h1 class="text-sm md:text-2xl font-bold text-slate-900 truncate">Tratativa do Pedido #<%= @order["orderId"] %></h1>
                    <!-- Status Tags no Header para máxima visibilidade -->
                    <%= if not Enum.empty?(@order_tags) do %>
                      <div class="flex items-center space-x-1 flex-wrap">
                        <%= for tag <- @order_tags do %>
                          <div class="flex items-center bg-white border border-slate-200 rounded-lg px-2 py-1 shadow-sm">
                            <div class="w-1.5 h-1.5 rounded-full mr-1.5" style={"background-color: #{tag.color}"}></div>
                            <span class="text-xs font-bold text-slate-700"><%= tag.name %></span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <div class="flex flex-wrap items-center mt-1 space-x-2 md:space-x-4">
                  <div class="flex items-center">
                    <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
                    <span class="text-xs text-slate-600 font-medium"><%= @connection_status %></span>
                  </div>
                  <div class="flex items-center text-xs text-slate-500">
                    <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                    </svg>
                    <%= @message_count %> msgs
                  </div>
                  <div class="flex items-center text-xs text-slate-500">
                    <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
                    </svg>
                    <%= length(@users_online) %> online
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="flex items-center space-x-1 mt-2 md:mt-0">
            <button phx-click="toggle_search" class="p-1.5 md:p-2.5 text-slate-500 hover:text-slate-700 transition-all duration-200 rounded-lg hover:bg-slate-100 hover:shadow-sm"
                    aria-label="Buscar mensagens"
                    title="Buscar mensagens">
              <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
            </button>
            <button class="p-1.5 md:p-2.5 text-slate-500 hover:text-slate-700 transition-all duration-200 rounded-lg hover:bg-slate-100 hover:shadow-sm"
                    aria-label="Exportar conversa"
                    title="Exportar conversa">
              <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
              </svg>
            </button>
            <button class="p-1.5 md:p-2.5 text-slate-500 hover:text-slate-700 transition-all duration-200 rounded-lg hover:bg-slate-100 hover:shadow-sm"
                    aria-label="Mais opções"
                    title="Mais opções">
              <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h.01M12 12h.01M19 12h.01M6 12a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0z"></path>
              </svg>
            </button>
          </div>
        </header>

        <!-- Error Message -->
        <%= if @message_error do %>
          <div class="mx-4 md:mx-6 mt-4 p-3 md:p-4 bg-red-50 border border-red-200 rounded-lg flex items-center justify-between animate-pulse">
            <div class="flex items-center">
              <svg class="w-5 h-5 text-red-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <span class="text-sm text-red-700"><%= @message_error %></span>
            </div>
            <button phx-click="clear_error" class="text-red-500 hover:text-red-700 transition-colors">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        <% end %>

        <!-- Search Bar -->
        <%= if @show_search do %>
          <div class="mx-4 md:mx-6 mt-4 p-3 md:p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <div class="flex items-center space-x-2">
              <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
              <input
                type="text"
                placeholder="Buscar nas mensagens..."
                class="flex-1 px-3 py-2 border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                phx-keyup="search_messages"
                phx-debounce="300"
              />
              <button phx-click="toggle_search" class="text-blue-500 hover:text-blue-700">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>
          </div>
        <% end %>

        <!-- Messages Container -->
        <div id="messages"
             class="flex-1 overflow-y-auto px-3 py-3 md:px-12 md:py-8 bg-gradient-to-b from-slate-50/30 to-white scroll-smooth min-h-0"
             role="log"
             aria-live="polite"
             aria-label="Mensagens do chat">

          <!-- Load More Button -->
          <%= if @has_more_messages do %>
            <div class="flex justify-center pb-6">
              <button
                phx-click="load_older_messages"
                disabled={@loading_messages}
                class="px-4 py-2 text-sm text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-2 shadow-sm hover:shadow-md">
                <%= if @loading_messages do %>
                  <svg class="w-4 h-4 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  <span>Carregando...</span>
                <% else %>
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"></path>
                  </svg>
                  <span>Carregar mensagens anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <%= if Enum.empty?(@messages) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-12">
              <div class="w-20 h-20 bg-gradient-to-br from-blue-100 to-indigo-100 rounded-full flex items-center justify-center mb-6 shadow-sm">
                <svg class="w-10 h-10 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
              </div>
              <h2 class="text-xl font-semibold text-gray-900 mb-3">Nenhuma mensagem ainda</h2>
              <p class="text-gray-600 max-w-md">Seja o primeiro a enviar uma mensagem neste chat do pedido!</p>
            </div>
          <% else %>
            <%= for {message, index} <- Enum.with_index(@messages) do %>
              <%
                is_current_user = case @user_object do
                  nil -> false
                  user -> user.id == message.sender_id
                end

                previous_message = if index > 0, do: Enum.at(@messages, index - 1), else: nil
                show_date_separator = should_show_date_separator(message, previous_message)
              %>

              <%= if show_date_separator do %>
                <!-- Separador de Data -->
                <div class="flex items-center justify-center my-6">
                  <div class="bg-gray-100 text-gray-600 text-xs font-medium px-3 py-1 rounded-full shadow-sm">
                    <%= format_date_separator(message.timestamp || message.inserted_at) %>
                  </div>
                </div>
              <% end %>
              <div class={"flex mb-4 " <> if(is_current_user, do: "justify-end", else: "justify-start")}
                   role="article"
                   aria-label={"Mensagem de " <> message.sender_name}>

                <%= if not is_current_user do %>
                  <!-- Avatar do remetente -->
                  <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex items-center justify-center mr-2 flex-shrink-0 shadow-sm">
                    <span class="text-white text-xs font-bold"><%= get_user_initial(message.sender_name) %></span>
                  </div>
                <% end %>

                <div class={
                  "relative max-w-[85%] sm:max-w-md lg:max-w-lg xl:max-w-xl px-3 md:px-4 py-2 md:py-3 rounded-2xl shadow-sm transition-all duration-200 " <>
                  if(is_current_user,
                    do: "bg-gradient-to-br from-green-500 to-green-600 text-white rounded-br-md",
                    else: "bg-white text-gray-900 rounded-bl-md border border-gray-200")
                }>
                  <%= if not is_current_user do %>
                    <div class="text-xs font-semibold text-gray-600 mb-1 opacity-75"><%= message.sender_name %></div>
                  <% end %>
                  <div class="text-sm break-words leading-relaxed"><%= format_message_with_mentions(message.text) %></div>
                  <%= if message.image_url do %>
                    <img src={message.image_url}
                         class="w-32 h-32 object-cover rounded-lg cursor-pointer hover:scale-105 transition mt-2"
                         phx-click="show_image"
                         phx-value-url={message.image_url}
                         alt="Imagem enviada" />
                  <% end %>
                  <div class="flex items-center justify-end mt-2 space-x-1">
                    <span class={"text-xs " <> if(is_current_user, do: "text-white/70", else: "text-gray-400")}><%= format_time(message.inserted_at) %></span>
                    <%= if is_current_user do %>
                      <svg class="w-3 h-3 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                      </svg>
                    <% end %>
                  </div>
                </div>

                <%= if is_current_user do %>
                  <!-- Avatar do usuário atual -->
                  <div class="w-8 h-8 bg-gradient-to-br from-gray-500 to-gray-700 rounded-full flex items-center justify-center ml-2 flex-shrink-0 shadow-sm">
                    <span class="text-white text-xs font-bold"><%= get_user_initial(@current_user) %></span>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Typing Indicator -->
        <%= if @show_typing_indicator && @typing_users && length(@typing_users) > 0 do %>
          <div class="px-4 md:px-6 py-2 bg-gray-50/50 border-t border-gray-100">
            <div class="flex items-center space-x-2">
              <div class="flex space-x-1">
                <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
              </div>
              <span class="text-xs text-gray-500">
                <%= Enum.join(@typing_users, ", ") %> está digitando...
              </span>
            </div>
          </div>
        <% end %>

        <!-- Message Input -->
        <footer class="p-3 md:p-6 border-t border-gray-200 bg-white/95 backdrop-blur-sm flex-shrink-0 shadow-lg">
          <!-- Status de Conexão -->
          <div class="mb-2 flex items-center justify-between text-xs">
            <div class="flex items-center space-x-2">
              <div class={get_connection_indicator_class(@connected)}></div>
              <span class={get_connection_text_class(@connected)}>
                {if @connected, do: "Conectado", else: "Desconectado"}
              </span>
            </div>
            <%= if @message_error do %>
              <div class="text-red-500 font-medium">{@message_error}</div>
            <% end %>
          </div>

          <form phx-submit="send_message" phx-drop-target={@uploads.image.ref} class="flex items-end space-x-2 md:space-x-6" role="form" aria-label="Enviar mensagem">
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>
              <!-- Preview da imagem -->
              <%= if @uploads[:image] && @uploads.image.entries != [] do %>
                <div class="mb-2 flex items-center space-x-2">
                  <%= for entry <- @uploads.image.entries do %>
                    <div class="relative inline-block mr-2 mb-2">
                      <!-- Preview da imagem -->
                      <.live_img_preview entry={entry} class="w-20 h-20 object-cover rounded-lg border border-gray-200 shadow" />

                      <!-- Barra de progresso animada -->
                      <div class="absolute bottom-0 left-0 w-full h-2 bg-gray-200 rounded-b-lg overflow-hidden">
                        <div class={"h-full bg-blue-500 transition-all duration-300 #{if entry.progress >= 100, do: "w-full", else: "w-0"}"}></div>
                      </div>

                      <!-- Ícone de carregando enquanto não terminou -->
                      <%= if entry.progress < 100 do %>
                        <div class="absolute inset-0 flex items-center justify-center bg-white/60 rounded-lg">
                          <svg class="animate-spin w-6 h-6 text-blue-500" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                          </svg>
                        </div>
                      <% end %>

                      <!-- Botão para remover o upload -->
                      <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                              class="absolute top-0 right-0 bg-white/80 rounded-full p-1 text-red-500 hover:text-red-700" title="Remover imagem">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <input
                id="message-input"
                name="message"
                value={@message}
                placeholder="Digite sua mensagem..."
                class="w-full px-3 md:px-6 py-2.5 md:py-4 pr-8 md:pr-12 border border-gray-300 rounded-2xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-gray-400 hover:shadow-md text-sm md:text-base"
                autocomplete="off"
                maxlength={ChatConfig.security_config()[:max_message_length]}
                required
                disabled={not @connected}
                phx-change="update_message"
              />

              <!-- Autocomplete para menções -->
              <div id="mention-suggestions" class="hidden absolute bottom-full left-0 right-0 mb-2 bg-white border border-gray-200 rounded-lg shadow-lg max-h-48 overflow-y-auto z-10" style="z-index:9999; position:absolute;">
                <div class="p-2 text-xs text-gray-500 border-b border-gray-100">
                  Usuários online
                </div>
                <div id="mention-suggestions-list" class="py-1">
                  <!-- Sugestões serão inseridas aqui via JavaScript -->
                </div>
              </div>
              <label for="image-upload" class="absolute right-1.5 md:right-3 top-1/2 transform -translate-y-1/2 p-1 md:p-1.5 text-gray-400 hover:text-gray-600 transition-all duration-200 rounded-lg hover:bg-gray-100 cursor-pointer" aria-label="Anexar arquivo" title="Anexar arquivo">
                <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                </svg>
                <input
                  id="image-upload"
                  type="file"
                  name="image"
                  accept="image/*"
                  class="hidden"
                  phx-drop-target={@uploads.image.ref}
                  multiple={false}
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={String.trim(@message) == "" && @uploads.image.entries == []}
              class="px-3 md:px-8 py-2.5 md:py-4 bg-gradient-to-r from-slate-700 to-slate-900 text-white rounded-2xl hover:from-slate-800 hover:to-slate-950 focus:ring-2 focus:ring-slate-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-1 md:space-x-3 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed transform hover:scale-105 phx-submit-loading:opacity-75 text-sm md:text-base"
              aria-label="Enviar mensagem"
              title={"Mensagem: '#{@message}', Conectado: #{@connected}, Uploads: #{length(@uploads.image.entries)}"}>
              <span class="hidden sm:inline">Enviar</span>
              <span class="sm:hidden">→</span>
              <svg class="w-4 h-4 md:w-5 md:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
              </svg>
            </button>


          </form>
        </footer>
      </main>
    </div>

    <!-- Overlay para mobile quando sidebar está aberta -->
    <%= if @show_sidebar do %>
      <div class="fixed inset-0 bg-black/50 z-20 md:hidden" phx-click="toggle_sidebar" aria-hidden="true"></div>
    <% end %>

    <%= if @modal_image_url do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70" phx-click="close_image_modal">
        <div class="relative" phx-click="stopPropagation">
          <img src={@modal_image_url} class="max-h-[80vh] max-w-[90vw] rounded-lg shadow-2xl border-4 border-white" alt="Imagem ampliada" />
          <button class="absolute top-2 right-2 bg-white/80 rounded-full p-2 text-gray-700 hover:text-red-600" phx-click="close_image_modal">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
      </div>
    <% end %>

    <!-- Modal para adicionar tags -->
    <%= if @show_tag_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" phx-click="hide_tag_modal">
        <div class="bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[80vh] overflow-hidden" phx-click="stopPropagation">
          <!-- Header do modal -->
          <div class="flex items-center justify-between p-6 border-b border-slate-200">
            <h3 class="text-xl font-bold text-slate-900">Adicionar Tag</h3>
            <button phx-click="hide_tag_modal" class="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-all duration-200">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Conteúdo do modal -->
          <div class="p-6">
            <!-- Campo de busca -->
            <div class="mb-6">
              <label class="block text-sm font-medium text-slate-700 mb-2">Filtrar tags</label>
              <div class="relative">
                <input type="text"
                       phx-keyup="search_tags"
                       phx-debounce="300"
                       value={@tag_search_query}
                       placeholder="Digite para filtrar tags..."
                       class="w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-slate-500 transition-all duration-200 text-sm" />
                <div class="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                  <svg class="w-5 h-5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                  </svg>
                </div>
              </div>
            </div>

            <!-- Lista de resultados -->
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <%= if Enum.empty?(@tag_search_results) do %>
                <p class="text-sm text-slate-500 text-center py-4">Nenhuma tag disponível</p>
              <% else %>
                <%= for tag <- @tag_search_results do %>
                  <div class="flex items-center justify-between p-3 bg-slate-50 rounded-lg hover:bg-slate-100 transition-all duration-200">
                    <div class="flex items-center">
                      <div class="w-3 h-3 rounded-full mr-3" style={"background-color: #{tag.color}"}></div>
                      <span class="text-sm font-medium text-slate-700"><%= tag.name %></span>
                      <%= if tag.description do %>
                        <span class="text-xs text-slate-500 ml-2">(<%= tag.description %>)</span>
                      <% end %>
                    </div>
                    <button phx-click="add_tag_to_order"
                            phx-value-tag_id={tag.id}
                            class="px-3 py-1.5 bg-slate-600 text-white text-xs font-medium rounded-lg hover:bg-slate-700 transition-all duration-200">
                      Adicionar
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Utility Functions ---

  defp extract_users_from_presences(presences) do
    presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{name: name} -> name end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp load_older_messages_async(socket) do
    order_id = socket.assigns.order_id
    current_count = length(socket.assigns.messages)

    Task.start(fn ->
      case App.Chat.list_messages_for_order(order_id, ChatConfig.pagination_config()[:default_limit], current_count) do
        {:ok, older_messages, has_more} ->
          send(self(), {:older_messages_loaded, older_messages, has_more})
      end
    end)

    socket
  end

  # --- UI Formatting & Display Helpers ---

  defp get_user_initial(user) when is_binary(user) and byte_size(user) > 0 do
    user |> String.first() |> String.upcase()
  end
  defp get_user_initial(_), do: "U"

  defp get_status_class(status) do
    base_classes = "px-3 py-1.5 text-xs font-semibold rounded-full border shadow-sm"

    case String.downcase(status || "") do
      "ativo" -> "#{base_classes} bg-emerald-100 text-emerald-800 border-emerald-200"
      "pendente" -> "#{base_classes} bg-amber-100 text-amber-800 border-amber-200"
      "cancelado" -> "#{base_classes} bg-red-100 text-red-800 border-red-200"
      "concluído" -> "#{base_classes} bg-slate-100 text-slate-800 border-slate-200"
      _ -> "#{base_classes} bg-slate-100 text-slate-800 border-slate-200"
    end
  end

  defp get_connection_indicator_class(connected) do
    base_classes = "w-1.5 h-1.5 rounded-full mr-1.5"
    if connected, do: "#{base_classes} bg-emerald-500 animate-pulse", else: "#{base_classes} bg-red-500"
  end

  defp get_connection_text_class(connected) do
    if connected, do: "text-emerald-600", else: "text-red-600"
  end

  defp format_currency(amount) when is_binary(amount) and byte_size(amount) > 0 do
    case Float.parse(amount) do
      {float_amount, _} -> :erlang.float_to_binary(float_amount, decimals: 2)
      :error -> amount
    end
  end
  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end
  defp format_currency(_), do: "0.00"

  defp format_date(date_string) when is_binary(date_string) and byte_size(date_string) > 0 do
    case DateTimeHelper.parse_date_string(date_string) do
      %DateTime{} = datetime -> DateTimeHelper.format_date_br(datetime)
      _ -> date_string
    end
  end
  defp format_date(_), do: "Data não disponível"

  defp format_time(datetime) do
    DateTimeHelper.format_time_br(datetime)
  end

  defp format_date_separator(datetime) do
    case DateTimeHelper.to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt ->
        now = DateTimeHelper.now()
        today = DateTime.to_date(now)
        yesterday = Date.add(today, -1)
        message_date = DateTime.to_date(dt)

        cond do
          Date.compare(message_date, today) == :eq ->
            "Hoje"
          Date.compare(message_date, yesterday) == :eq ->
            "Ontem"
          true ->
            DateTimeHelper.format_date_br(dt)
        end
      _ ->
        "Data não disponível"
    end
  end

  defp should_show_date_separator(current_message, previous_message) do
    case {current_message, previous_message} do
      {_current, nil} ->
        true
      {current, previous} ->
        current_date = get_message_date(current)
        previous_date = get_message_date(previous)
        Date.compare(current_date, previous_date) != :eq
    end
  end

  defp get_message_date(message) do
    case DateTimeHelper.to_sao_paulo_timezone(message.timestamp || message.inserted_at) do
      %DateTime{} = dt -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end
end
