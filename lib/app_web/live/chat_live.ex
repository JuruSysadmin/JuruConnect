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
  Initializes the chat LiveView for a specific treaty.

  Sets up real-time subscriptions, loads treaty data and message history,
  and configures user presence tracking. Handles both authenticated and
  anonymous users with appropriate permission levels.
  """
  @impl true
  def mount(%{"treaty_id" => treaty_id} = _params, session, socket) do
    topic = "treaty:#{treaty_id}"

    Logger.info("Socket assigns current_user: #{inspect(socket.assigns[:current_user])}")
    Logger.info("Session user_token: #{inspect(session["user_token"])}")

    {current_user_name, authenticated_user} = resolve_user_identity(socket, session)

    if connected?(socket) do
      setup_pubsub_subscriptions(topic, authenticated_user)
      setup_presence_tracking(topic, socket, current_user_name, authenticated_user, treaty_id)
      schedule_connection_status_update()
    end

    treaty_data = fetch_treaty_with_fallback(treaty_id)
    {message_history, has_more_messages} = load_paginated_messages(treaty_id)
    treaty_tags = Tags.get_treaty_tags(treaty_id)
    current_presences = Presence.list(topic)
    online_users = extract_users_from_presences(current_presences)

    if authenticated_user do
      App.Accounts.record_order_access(authenticated_user.id, treaty_id)
      # Mark notifications as read when entering chat
      App.Notifications.mark_all_notifications_as_read(authenticated_user.id)
    end

    socket = assign_initial_socket_data(socket, %{
      treaty_id: treaty_id,
      treaty: treaty_data,
      messages: message_history,
      has_more_messages: has_more_messages,
      treaty_tags: treaty_tags,
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
      %{} = user -> extract_user_from_socket_assigns(user)
    end
  end

  defp extract_user_from_session_token(session) do
    case session["user_token"] do
      nil ->
        Logger.info("No token found in session")
        {ChatConfig.default_username(), nil}

      token when is_binary(token) ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, %{name: name} = user, _claims} when not is_nil(name) ->
            Logger.info("User found via token: #{name}")
            {name, user}

          {:ok, %{username: username} = user, _claims} when not is_nil(username) ->
            Logger.info("User found via token: #{username}")
            {username, user}

          {:ok, user, _claims} ->
            Logger.info("User found via token: #{ChatConfig.default_username()}")
            {ChatConfig.default_username(), user}

          {:error, reason} ->
            Logger.error("Token decode error: #{inspect(reason)}")
            {ChatConfig.default_username(), nil}
        end
    end
  end

  defp extract_user_from_socket_assigns(%{name: name} = user) when not is_nil(name) do
    Logger.info("User authenticated via on_mount: #{name} (ID: #{user.id})")
    {name, user}
  end

  defp extract_user_from_socket_assigns(%{username: username} = user) when not is_nil(username) do
    Logger.info("User authenticated via on_mount: #{username} (ID: #{user.id})")
    {username, user}
  end

  defp extract_user_from_socket_assigns(user) do
    default_name = ChatConfig.default_username()
    Logger.info("User authenticated via on_mount: #{default_name} (ID: #{user.id})")
    {default_name, user}
  end

  # --- Real-time Communication Setup ---

  defp setup_pubsub_subscriptions(topic, authenticated_user) do
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    if authenticated_user do
      Phoenix.PubSub.subscribe(App.PubSub, "user:#{authenticated_user.id}")
    end
  end

  defp setup_presence_tracking(topic, socket, user_name, authenticated_user, treaty_id) do
    user_data = %{
      user_id: get_user_id_for_presence(authenticated_user),
      name: user_name,
      joined_at: DateTimeHelper.now() |> DateTime.to_iso8601(),
      user_agent: get_connect_info(socket, :user_agent) || "Unknown"
    }

    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
        Logger.info("User #{user_name} joined chat for treaty #{treaty_id}")
        # Also track in active rooms system
        if authenticated_user do
          case Process.whereis(App.ActiveRooms) do
            nil ->
              Logger.warning("ActiveRooms GenServer not available")
            _pid ->
              try do
                App.ActiveRooms.join_room(treaty_id, authenticated_user.id, user_name)
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

  defp get_user_id_for_presence(nil), do: "anonymous"
  defp get_user_id_for_presence(%{id: id}), do: id

  defp schedule_connection_status_update do
    Process.send_after(self(), :update_connection_status, 5000)
  end

  # --- Data Loading & Management ---

  defp fetch_treaty_with_fallback(treaty_id) when is_binary(treaty_id) do
    case App.Treaties.get_treaty(treaty_id) do
      {:ok, treaty} -> treaty
      {:error, _} ->
        %App.Treaties.Treaty{
          treaty_code: treaty_id,
          status: "Não encontrado",
          title: "N/A",
          description: "N/A",
          priority: "N/A",
          created_by: nil,
          store_id: nil
        }
    end
  end

  defp load_paginated_messages(treaty_id) when is_binary(treaty_id) do
    case App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.default_message_limit()) do
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
    is_connected = connected?(socket)
    connection_status = if is_connected, do: "Conectado", else: "Desconectado"

    socket
    |> assign_initial_data(data)
    |> assign_connection_state(is_connected, connection_status)
    |> assign_ui_state()
    |> allow_upload(:image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1, max_file_size: 5_000_000)
  end

  defp assign_initial_data(socket, data) do
    socket
    |> assign(:treaty_id, data.treaty_id)
    |> assign(:treaty, data.treaty)
    |> assign(:messages, data.messages)
    |> assign(:has_more_messages, data.has_more_messages)
    |> assign(:treaty_tags, data.treaty_tags)
    |> assign(:presences, data.presences)
    |> assign(:users_online, data.users_online)
    |> assign(:current_user, data.current_user)
    |> assign(:user_object, data.user_object)
    |> assign(:token, data.token)
    |> assign(:topic, data.topic)
    |> assign(:message_count, length(data.messages))
  end

  defp assign_connection_state(socket, is_connected, connection_status) do
    socket
    |> assign(:connected, is_connected)
    |> assign(:connection_status, connection_status)
  end

  defp assign_ui_state(socket) do
    socket
    |> assign(:message, "")
    |> assign(:loading_messages, false)
    |> assign(:message_error, nil)
    |> assign(:modal_image_url, nil)
    |> assign(:typing_users, [])
    |> assign(:show_typing_indicator, false)
    |> assign(:show_search, false)
    |> assign(:show_tag_modal, false)
    |> assign(:tag_search_query, "")
    |> assign(:tag_search_results, [])
    |> assign(:show_sidebar, false)
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
    with {:ok, _} <- validate_message_not_empty(trimmed_text, socket),
         {:ok, _} <- validate_message_length(trimmed_text),
         {:ok, _} <- validate_connection(socket) do
      {:ok, :valid}
    end
  end

  defp validate_message_not_empty("", socket) when map_size(socket.assigns.uploads.image.entries) == 0 do
    {:error, "Mensagem não pode estar vazia"}
  end
  defp validate_message_not_empty(_text, _socket), do: {:ok, :valid}

  defp validate_message_length(text) do
    max_length = ChatConfig.security_config()[:max_message_length]

    if byte_size(text) > max_length do
      {:error, "Mensagem muito longa"}
    else
      {:ok, :valid}
    end
  end

  defp validate_connection(socket) do
    if not connected?(socket) do
      {:error, "Conexão perdida. Tente recarregar a página."}
    else
      {:ok, :valid}
    end
  end

  defp process_message_send(socket, trimmed_text) do
    file_info = process_image_upload(socket)
    {user_id, user_name} = extract_user_info_for_message(socket)

    case App.Chat.send_message(socket.assigns.treaty_id, user_id, trimmed_text, file_info) do
      {:ok, _message} ->
        Logger.info("Message sent by #{user_name} in treaty #{socket.assigns.treaty_id}")
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
    Logger.info("Processing image upload")
    Logger.info("Upload entries: #{inspect(socket.assigns.uploads.image.entries)}")

    result = consume_uploaded_entries(socket, :image, fn %{path: path, client_name: name}, entry ->
      Logger.info("Processing uploaded file: #{name} at #{path}")
      case App.ImageUpload.upload_image(path, name) do
        {:ok, url} ->
          Logger.info("Image uploaded successfully: #{url}")
          %{
            filename: Path.basename(url),
            original_filename: name,
            file_size: entry.client_size,
            mime_type: entry.client_type,
            file_url: url
          }
        {:error, reason} ->
          Logger.error("Erro no upload da imagem: #{inspect(reason)}")
          nil
      end
    end)
    |> List.first()

    Logger.info("Image upload result: #{inspect(result)}")
    result
  end

  defp extract_user_info_for_message(socket) do
    case socket.assigns[:user_object] do
      nil ->
        {nil, socket.assigns.current_user}

      %{id: id, name: name} when not is_nil(name) ->
        {id, name}

      %{id: id, username: username} when not is_nil(username) ->
        {id, username}

      %{id: id} ->
        {id, socket.assigns.current_user}
    end
  end

  @doc """
  Loads additional message history for the current treaty.

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
    # Navegar de volta para a tela de busca de tratativas
    {:noreply, push_navigate(socket, to: "/buscar-tratativa")}
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
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload", _params, socket) do
    Logger.info("Upload event received")
    Logger.info("Uploads in socket: #{inspect(socket.assigns.uploads)}")
    {:noreply, socket}
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
  def handle_event("add_tag_to_treaty", %{"tag_id" => tag_id}, socket) do
    user_id = socket.assigns.user_object.id

          case Tags.add_tag_to_treaty(socket.assigns.treaty_id, tag_id, user_id) do
        {:ok, _treaty_tag} ->
          treaty_tags = Tags.get_treaty_tags(socket.assigns.treaty_id)
          {:noreply,
            socket
            |> assign(:treaty_tags, treaty_tags)
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
  def handle_event("remove_tag_from_treaty", %{"tag_id" => tag_id}, socket) do
    case Tags.remove_tag_from_treaty(socket.assigns.treaty_id, tag_id) do
      {count, nil} when count > 0 ->
        treaty_tags = Tags.get_treaty_tags(socket.assigns.treaty_id)
        {:noreply,
          socket
          |> assign(:treaty_tags, treaty_tags)
          |> put_flash(:info, "Tag removida com sucesso!")
        }
      _ ->
        {:noreply, put_flash(socket, :error, "Erro ao remover tag")}
    end
  end

  @doc """
  Handles incoming messages from PubSub and updates the UI.

  Filters messages for the current treaty and provides visual/audio
  notifications for messages from other users to enhance real-time collaboration.
  """
  @impl true
  def handle_info({:new_message, msg}, socket) do
    if msg.treaty_id == socket.assigns.treaty_id do
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
    # Only show notification if user is not in the current chat
    current_treaty_id = socket.assigns.treaty_id

    if notification_data.treaty_id != current_treaty_id do
      {:noreply,
        socket
        |> push_event("show-notification", %{
          title: "Nova mensagem",
          body: "#{notification_data.sender_name}: #{String.slice(notification_data.text, 0, 50)}",
          icon: "/images/notification-icon.svg",
          data: %{
            treaty_id: notification_data.treaty_id,
            message_id: notification_data.message.id
          }
        })
        |> push_event("update-badge-count", %{})
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:notification, :mention, notification_data}, socket) do
    # Always show mention notifications
    {:noreply,
      socket
      |> push_event("show-notification", %{
        title: "Você foi mencionado!",
        body: "#{notification_data.sender_name} mencionou você: #{String.slice(notification_data.text, 0, 50)}",
        icon: "/images/notification-icon.svg",
        data: %{
          treaty_id: notification_data.treaty_id,
          message_id: notification_data.message.id
        }
      })
      |> push_event("play-notification-sound", %{})
      |> push_event("update-badge-count", %{})
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
            App.ActiveRooms.leave_room(socket.assigns.treaty_id, socket.assigns.user_object.id)
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
            App.ActiveRooms.leave_room(socket.assigns.treaty_id, socket.assigns.user_object.id)
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
         class="min-h-screen w-full bg-gray-50 font-sans antialiased flex flex-col lg:flex-row overflow-hidden m-0 p-0 relative"
         phx-hook="ChatHook"
         role="main">


      <!-- Área principal do chat -->
      <main class="flex-1 h-full lg:h-screen flex flex-col bg-white min-w-0 lg:border-l border-gray-200 max-w-none m-0 p-0 shadow-lg" role="main" aria-label="Área de chat">
        <!-- Header do Chat -->
        <header class="flex flex-col sm:flex-row items-start sm:items-center justify-between px-4 sm:px-6 py-3 sm:py-4 border-b border-gray-200 bg-gradient-to-r from-white to-gray-50 flex-shrink-0 shadow-sm">
          <div class="flex items-center w-full">
            <div class="flex items-center space-x-2 flex-1 min-w-0">
              <div class="w-8 h-8 sm:w-10 sm:h-10 bg-gradient-to-br from-blue-600 to-blue-800 rounded-xl flex items-center justify-center shadow-lg">
                <svg class="w-5 h-5 sm:w-6 sm:h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex flex-col space-y-0.5">
                  <div class="flex items-center space-x-2">
                    <h1 class="text-base sm:text-lg md:text-xl font-bold text-gray-900 truncate">Tratativa #<%= @treaty.treaty_code %></h1>
                    <span class={get_status_class(@treaty.status)}>
                      <%= @treaty.status %>
                    </span>
                  </div>
                  <!-- Status Tags no Header -->
                  <%= if not Enum.empty?(@treaty_tags) do %>
                    <div class="flex items-center space-x-1 flex-wrap">
                      <%= for tag <- @treaty_tags do %>
                        <div class="flex items-center bg-gray-100 border border-gray-200 rounded-lg px-2 py-1 shadow-sm">
                          <div class="w-2 h-2 rounded-full mr-2" style={"background-color: #{tag.color}"}></div>
                          <span class="text-xs font-semibold text-gray-700"><%= tag.name %></span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="flex flex-wrap items-center mt-2 space-x-2 sm:space-x-4">
                  <div class="flex items-center">
                    <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
                    <span class="text-sm text-gray-600 font-medium"><%= @connection_status %></span>
                  </div>
                  <div class="flex items-center text-sm text-gray-500">
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
                    </svg>
                    <span class="font-medium"><%= length(@users_online) %> online</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

           <div class="flex items-center space-x-1 sm:space-x-2 mt-2 sm:mt-0">
            <button phx-click="toggle_search" class="p-1.5 sm:p-2 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg hover:shadow-sm"
                    aria-label="Buscar mensagens"
                    title="Buscar mensagens">
              <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
            </button>
            <button
              phx-click="exit_chat"
              class="p-1.5 sm:p-2 text-gray-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm"
              title="Sair do chat e voltar para busca de tratativas"
              aria-label="Sair do chat"
            >
              <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path>
              </svg>
            </button>
          </div>
        </header>

        <!-- Error Message -->
        <%= if @message_error do %>
          <div class="mx-2 md:mx-3 mt-2 p-2 bg-red-50 border border-red-200 rounded flex items-center justify-between">
            <div class="flex items-center">
              <svg class="w-4 h-4 text-red-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <span class="text-xs text-red-700"><%= @message_error %></span>
            </div>
            <button phx-click="clear_error" class="text-red-500 hover:text-red-700 transition-colors">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        <% end %>

        <!-- Search Bar -->
        <%= if @show_search do %>
          <div class="mx-2 sm:mx-3 mt-2 p-2 bg-blue-50 border border-blue-200 rounded-lg">
            <div class="flex items-center space-x-2">
              <svg class="w-4 h-4 text-blue-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
              <input
                type="text"
                placeholder="Buscar nas mensagens..."
                class="flex-1 px-2 py-1.5 text-xs border border-blue-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                phx-keyup="search_messages"
                phx-debounce="300"
                aria-label="Buscar mensagens"
              />
              <button phx-click="toggle_search" class="text-blue-500 hover:text-blue-700 p-1" aria-label="Fechar busca">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>
          </div>
        <% end %>

        <!-- Messages Container -->
        <div class="flex-1 flex overflow-hidden">
          <div id="messages"
               class="flex-1 overflow-y-auto px-3 sm:px-4 md:px-8 py-4 sm:py-6 md:py-8 bg-gradient-to-b from-gray-50/50 to-white scroll-smooth min-h-0"
               role="log"
               aria-live="polite"
               aria-label="Mensagens do chat">

          <!-- Load More Button -->
          <%= if @has_more_messages do %>
            <div class="flex justify-center pb-3">
              <button
                phx-click="load_older_messages"
                disabled={@loading_messages}
                class="px-3 py-1.5 text-xs text-gray-600 bg-white border border-gray-200 rounded hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-1 shadow-sm hover:shadow-md transform hover:-translate-y-0.5">
                <%= if @loading_messages do %>
                  <svg class="w-3 h-3 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  <span>Carregando...</span>
                <% else %>
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"></path>
                  </svg>
                  <span>Carregar anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <%= if Enum.empty?(@messages) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-6 animate-fade-in">
              <div class="w-12 h-12 bg-gradient-to-br from-blue-100 to-indigo-100 rounded-full flex items-center justify-center mb-3 shadow-sm animate-bounce">
                <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
              </div>
              <h2 class="text-sm font-semibold text-gray-900 mb-2">Nenhuma mensagem ainda</h2>
              <p class="text-xs text-gray-600 max-w-md">Seja o primeiro a enviar uma mensagem!</p>
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
                <div class="flex items-center justify-center my-4">
                  <div class="bg-gray-100 text-gray-600 text-xs font-medium px-3 py-1 rounded-full shadow-sm border border-gray-200">
                    <%= format_date_separator(message.timestamp || message.inserted_at) %>
                  </div>
                </div>
              <% end %>
              <div class={"flex mb-3 animate-slide-in " <> if(is_current_user, do: "justify-end", else: "justify-start")}
                   role="article"
                   aria-label={"Mensagem de " <> message.sender_name}>


                <div class={
                  "relative max-w-[90%] sm:max-w-[85%] md:max-w-md lg:max-w-lg xl:max-w-xl px-3 sm:px-4 py-2.5 sm:py-3 rounded-xl shadow-md transition-all duration-200 hover:shadow-lg " <>
                  if(is_current_user,
                    do: "bg-gradient-to-br from-blue-500 to-blue-600 text-white rounded-br-lg",
                    else: "bg-white text-gray-900 rounded-bl-lg border border-gray-200 shadow-sm hover:border-gray-300")
                }>
                  <%= if not is_current_user do %>
                    <div class="text-sm font-semibold text-gray-700 mb-1"><%= message.sender_name %></div>
                  <% end %>
                  <div class="text-sm break-words leading-relaxed"><%= format_message_with_mentions(message.text) %></div>
                  <%= if message.attachments && length(message.attachments) > 0 do %>
                    <div class="mt-2 space-y-2">
                      <%= for attachment <- message.attachments do %>
                        <%= if attachment.file_type == "image" do %>
                          <img src={attachment.file_url}
                               class="w-24 h-24 object-cover rounded cursor-pointer hover:scale-105 transition-all duration-300 shadow-sm hover:shadow-md"
                               phx-click="show_image"
                               phx-value-url={attachment.file_url}
                               alt={attachment.original_filename} />
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                  <div class="flex items-center justify-end mt-1 space-x-1">
                    <span class={"text-xs " <> if(is_current_user, do: "text-white/70", else: "text-gray-400")}><%= format_time(message.inserted_at) %></span>
                    <%= if is_current_user do %>
                      <svg class="w-2.5 h-2.5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                      </svg>
                    <% end %>
                  </div>
                </div>

              </div>
            <% end %>
          <% end %>
          </div>

          <!-- Sidebar com usuários online e tags -->
          <div class="hidden lg:block w-64 bg-white border-l border-gray-200 overflow-y-auto">
            <!-- Seção de Tags -->
            <div class="p-4 border-b border-gray-200">
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-sm font-semibold text-gray-900">Tags</h3>
                <button phx-click="show_tag_modal"
                        class="p-1 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded"
                        aria-label="Gerenciar tags"
                        title="Gerenciar tags">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                  </svg>
                </button>
              </div>
              <%= if not Enum.empty?(@treaty_tags) do %>
                <div class="space-y-2">
                  <%= for tag <- @treaty_tags do %>
                    <div class="flex items-center justify-between p-2 bg-gray-50 rounded-lg">
                      <div class="flex items-center space-x-2">
                        <div class="w-3 h-3 rounded-full" style={"background-color: #{tag.color}"}></div>
                        <span class="text-sm font-medium text-gray-700"><%= tag.name %></span>
                      </div>
                      <button phx-click="remove_tag_from_treaty"
                              phx-value-tag_id={tag.id}
                              class="p-1 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-all duration-200"
                              title="Remover tag">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                        </svg>
                      </button>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-xs text-gray-500 text-center py-2">Nenhuma tag adicionada</p>
              <% end %>
            </div>

            <!-- Seção de Usuários Online -->
            <%= if not Enum.empty?(@users_online) do %>
              <div class="p-4">
                <h3 class="text-sm font-semibold text-gray-900 mb-3">Usuários Online</h3>
                <div class="space-y-2">
                  <%= for user <- @users_online do %>
                    <div class="flex items-center space-x-3 p-2 rounded-lg hover:bg-gray-50 transition-colors">
                      <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-700 rounded-full flex items-center justify-center shadow-sm">
                        <span class="text-white text-sm font-bold"><%= get_user_initial(user) %></span>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900 truncate"><%= user %></p>
                        <p class="text-xs text-green-600">Online</p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Rodapé da Sidebar com usuário atual -->
            <div class="mt-auto p-4 border-t border-gray-200 bg-gray-50">
              <div class="flex items-center space-x-3">
                <div class="w-8 h-8 bg-gradient-to-br from-green-500 to-green-700 rounded-full flex items-center justify-center shadow-sm">
                  <span class="text-white text-sm font-bold"><%= get_user_initial(@current_user) %></span>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-gray-900 truncate"><%= @current_user %></p>
                  <p class="text-xs text-gray-500">Você</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Typing Indicator -->
        <%= if @show_typing_indicator && @typing_users && length(@typing_users) > 0 do %>
          <div class="px-2 md:px-3 py-1 bg-gray-50/50 border-t border-gray-100">
            <div class="flex items-center space-x-1">
              <div class="flex space-x-0.5">
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce"></div>
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
              </div>
              <span class="text-xs text-gray-500">
                <%= Enum.join(@typing_users, ", ") %> digitando...
              </span>
            </div>
          </div>
        <% end %>

        <!-- Message Input -->
        <footer class="p-3 sm:p-4 border-t border-gray-200 bg-gradient-to-r from-white to-gray-50/50 backdrop-blur-sm flex-shrink-0 shadow-lg">
          <!-- Status de Conexão -->
          <div class="mb-1 flex items-center justify-between text-xs">
            <div class="flex items-center space-x-1" role="status" aria-live="polite">
              <div class={get_connection_indicator_class(@connected)} aria-hidden="true"></div>
              <span class={get_connection_text_class(@connected)}>
                {if @connected, do: "Conectado", else: "Desconectado"}
              </span>
            </div>
            <%= if @message_error do %>
              <div class="text-red-500 font-medium" role="alert" aria-live="assertive">{@message_error}</div>
            <% end %>
          </div>

          <form phx-submit="send_message" phx-drop-target={@uploads.image.ref} class="flex items-end space-x-2 sm:space-x-3 transition-all duration-200" role="form" aria-label="Enviar mensagem">
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>
              <!-- Drag and drop overlay -->
              <div class="absolute inset-0 bg-blue-50/80 border-2 border-dashed border-blue-300 rounded-xl flex items-center justify-center opacity-0 pointer-events-none transition-all duration-200 z-10" id="drag-overlay">
                <div class="text-center">
                  <svg class="w-8 h-8 text-blue-500 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
                  </svg>
                  <p class="text-sm font-medium text-blue-700">Solte a imagem aqui</p>
                  <p class="text-xs text-blue-500">JPG, PNG, GIF até 5MB</p>
                </div>
              </div>
              <!-- Preview da imagem -->
              <%= if @uploads[:image] && @uploads.image.entries != [] do %>
                <div class="mb-1 flex items-center space-x-1">
                  <%= for entry <- @uploads.image.entries do %>
                    <div class="relative inline-block mr-1 mb-1">
                      <!-- Preview da imagem -->
                      <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded border border-gray-200 shadow" />

                      <!-- Barra de progresso animada -->
                      <div class="absolute bottom-0 left-0 w-full h-1 bg-gray-200 rounded-b overflow-hidden">
                        <div class={"h-full bg-blue-500 transition-all duration-300 #{if entry.progress >= 100, do: "w-full", else: "w-0"}"}></div>
                      </div>

                      <!-- Ícone de carregando enquanto não terminou -->
                      <%= if entry.progress < 100 do %>
                        <div class="absolute inset-0 flex items-center justify-center bg-white/60 rounded">
                          <svg class="animate-spin w-4 h-4 text-blue-500" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                          </svg>
                        </div>
                      <% end %>

                      <!-- Botão para remover o upload -->
                      <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                              class="absolute top-0 right-0 bg-white/80 rounded-full p-0.5 text-red-500 hover:text-red-700" title="Remover imagem">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
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
                class="w-full px-3 sm:px-4 py-2.5 sm:py-3 pr-10 sm:pr-12 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-gray-400 text-sm"
                autocomplete="off"
                maxlength={ChatConfig.security_config()[:max_message_length]}
                required
                disabled={not @connected}
                phx-change="update_message"
                aria-describedby="message-help"
                aria-invalid={if @message_error, do: "true", else: "false"}
              />
              <div id="message-help" class="sr-only">
                Digite sua mensagem. Máximo de <%= ChatConfig.security_config()[:max_message_length] %> caracteres.
              </div>

              <!-- Autocomplete para menções -->
              <div id="mention-suggestions" class="hidden absolute bottom-full left-0 right-0 mb-1 bg-white border border-gray-200 rounded shadow-lg max-h-32 overflow-y-auto z-10" style="z-index:9999; position:absolute;">
                <div class="p-1 text-xs text-gray-500 border-b border-gray-100">
                  Usuários online
                </div>
                <div id="mention-suggestions-list" class="py-0.5">
                  <!-- Sugestões serão inseridas aqui via JavaScript -->
                </div>
              </div>
              <label for="image-upload" class="absolute right-2 sm:right-3 top-1/2 transform -translate-y-1/2 p-1.5 sm:p-2 text-gray-400 hover:text-blue-600 transition-all duration-200 rounded-lg hover:bg-blue-50 cursor-pointer" aria-label="Anexar arquivo" title="Anexar arquivo">
                <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                </svg>
                <input
                  id="image-upload"
                  type="file"
                  name="image"
                  accept="image/*"
                  class="hidden"
                  phx-drop-target={@uploads.image.ref}
                  phx-hook="ImageUploadHook"
                  phx-change="upload"
                  multiple={false}
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={String.trim(@message) == "" && @uploads.image.entries == []}
              class="px-4 sm:px-6 py-2.5 sm:py-3 bg-gradient-to-r from-blue-600 to-blue-700 text-white rounded-xl hover:from-blue-700 hover:to-blue-800 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-1 sm:space-x-2 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed phx-submit-loading:opacity-75 text-sm"
              aria-label="Enviar mensagem"
              aria-describedby="send-button-help"
              title="Enviar mensagem">
              <span class="hidden sm:inline">Enviar</span>
              <span class="sm:hidden">→</span>
              <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
              </svg>
            </button>
            <div id="send-button-help" class="sr-only">
              Botão para enviar mensagem. Disponível quando há texto ou imagem para enviar.
            </div>


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
                    <button phx-click="add_tag_to_treaty"
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
    |> Enum.flat_map(&extract_names_from_metas/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_names_from_metas(%{metas: metas}) do
    Enum.map(metas, fn %{name: name} -> name end)
  end

  defp load_older_messages_async(socket) do
    treaty_id = socket.assigns.treaty_id
    current_count = length(socket.assigns.messages)

    Task.start(fn ->
      case App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.pagination_config()[:default_limit], current_count) do
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
    base_classes = "px-2.5 py-1 text-xs font-semibold rounded-full border shadow-sm transition-all duration-200"

    case status do
      "ativo" -> "#{base_classes} bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100"
      "pendente" -> "#{base_classes} bg-amber-50 text-amber-700 border-amber-200 hover:bg-amber-100"
      "cancelado" -> "#{base_classes} bg-red-50 text-red-700 border-red-200 hover:bg-red-100"
      "concluído" -> "#{base_classes} bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
      _ -> "#{base_classes} bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
    end
  end

  defp get_connection_indicator_class(true) do
    "w-2 h-2 rounded-full mr-1.5 bg-emerald-500 animate-pulse shadow-sm"
  end
  defp get_connection_indicator_class(false) do
    "w-2 h-2 rounded-full mr-1.5 bg-red-500 shadow-sm"
  end

  defp get_connection_text_class(true), do: "text-emerald-600 font-medium"
  defp get_connection_text_class(false), do: "text-red-600 font-medium"


  defp format_time(datetime) do
    DateTimeHelper.format_time_br(datetime)
  end

  defp format_date_separator(datetime) do
    case DateTimeHelper.to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt ->
        format_relative_date(dt)
      _ ->
        "Data não disponível"
    end
  end

  defp format_relative_date(dt) do
    now = DateTimeHelper.now()
    today = DateTime.to_date(now)
    yesterday = Date.add(today, -1)
    message_date = DateTime.to_date(dt)

    case Date.compare(message_date, today) do
      :eq -> "Hoje"
      _ ->
        case Date.compare(message_date, yesterday) do
          :eq -> "Ontem"
          _ -> DateTimeHelper.format_date_br(dt)
        end
    end
  end

  defp should_show_date_separator(_current_message, nil), do: true

  defp should_show_date_separator(current_message, previous_message) do
    current_date = get_message_date(current_message)
    previous_date = get_message_date(previous_message)
    Date.compare(current_date, previous_date) != :eq
  end

  defp get_message_date(message) do
    case DateTimeHelper.to_sao_paulo_timezone(message.timestamp || message.inserted_at) do
      %DateTime{} = dt -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end
end
