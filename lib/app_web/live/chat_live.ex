defmodule AppWeb.ChatLive do
  @moduledoc """
  Componente LiveView para funcionalidade de chat em tempo real no gerenciamento de pedidos.

  Fornece interface de chat segura para discussões de pedidos com recursos como:
  - Mensagens em tempo real com PubSub
  - Rastreamento de presença de usuários
  - Suporte a upload de arquivos
  - Gerenciamento de tags para pedidos
  - Histórico de mensagens com paginação
  """
  use AppWeb, :live_view
  alias AppWeb.Presence
  alias App.ChatConfig
  alias App.Tags
  alias App.DateTimeHelper

  defstruct [:filename, :original_filename, :file_size, :mime_type, :file_url]

  @doc """
  Hook de autenticação que valida tokens de sessão do usuário.

  Garante acesso seguro verificando tokens Guardian dos dados de sessão
  antes de permitir participação no chat. Usuários anônimos são permitidos
  mas com funcionalidade limitada.
  """
  def on_mount(:default, _params, session, socket) do
    case session["user_token"] do
      nil ->
        {:cont, socket}

      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            {:cont, assign(socket, :current_user, user)}

          {:error, _reason} ->
            {:cont, socket}
        end
    end
  end

  @doc """
  Inicializa o LiveView de chat para uma tratativa específica.

  Configura assinaturas em tempo real, carrega dados da tratativa e histórico de mensagens,
  e configura rastreamento de presença de usuários. Lida com usuários autenticados e
  anônimos com níveis de permissão apropriados.
  """
  @impl true
  def mount(%{"treaty_id" => treaty_id} = _params, session, socket) do
    try do
      topic = "treaty:#{treaty_id}"
      {current_user_name, authenticated_user} = resolve_user_identity(socket, session)

      is_connected = connected?(socket)
      connection_status = if is_connected, do: "Conectado", else: "Desconectado"

      # Carregar tema do usuário com segurança
      user_theme = safely_load_user_theme(authenticated_user)

      socket = socket
      |> setup_connection_if_connected(topic, current_user_name, authenticated_user, treaty_id)
      |> load_initial_data(treaty_id, topic)
      |> handle_authenticated_user_actions(authenticated_user, treaty_id)
      |> assign(:treaty_id, treaty_id)
      |> assign(:current_user, current_user_name)
      |> assign(:user_object, authenticated_user)
      |> assign(:token, session["user_token"])
      |> assign(:topic, topic)
      |> assign(:user_theme, user_theme)
      |> assign_connection_state(is_connected, connection_status)
      |> assign_ui_state()
      |> allow_upload(:image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 3, max_file_size: 5_000_000, auto_upload: true)

      {:ok, socket}
    rescue
      error ->
        # Log o erro mas não faça crash do processo
        require Logger
        Logger.error("LiveView mount error for treaty #{treaty_id}: #{inspect(error)}")

        # Criar socket básico sem funcionalidades avançadas
        socket = socket
        |> assign(:treaty_id, treaty_id)
        |> assign(:current_user, "Usuario")
        |> assign(:user_object, nil)
        |> assign(:token, session["user_token"])
        |> assign(:topic, "treaty:#{treaty_id}")
        |> assign(:user_theme, nil)
        |> assign(:loading_error, true)
        |> assign_ui_state()

        {:ok, socket}
    end
  end

  # --- Funções Auxiliares para Mount ---

  defp setup_connection_if_connected(socket, topic, current_user_name, authenticated_user, treaty_id) do
    if connected?(socket) do
      setup_pubsub_subscriptions(topic, authenticated_user)
      setup_presence_tracking(topic, socket, current_user_name, authenticated_user, treaty_id)
      schedule_connection_status_update()
    end
    socket
  end

  defp load_initial_data(socket, treaty_id, topic) do
    try do
      treaty_data = fetch_treaty_with_fallback(treaty_id)
      {message_history, has_more_messages} = safely_load_paginated_messages(treaty_id)
      treaty_tags = safely_get_treaty_tags(treaty_id)
      current_presences = safely_get_presences(topic)
      online_users = extract_users_from_presences(current_presences || %{})

      # Carregar dados de ratings, atividades e estatísticas com segurança
      treaty_ratings = safely_get_treaty_ratings(treaty_data.id)
      treaty_activities = safely_get_treaty_activities(treaty_data.id, 20)
      treaty_stats = safely_get_treaty_stats(treaty_data.id)

      socket
      |> assign(:treaty, treaty_data)
      |> assign(:messages, message_history)
      |> assign(:has_more_messages, has_more_messages)
      |> assign(:treaty_tags, treaty_tags)
      |> assign(:presences, current_presences || %{})
      |> assign(:users_online, online_users)
      |> assign(:message_count, length(message_history))
      |> assign(:treaty_ratings, treaty_ratings)
      |> assign(:treaty_activities, treaty_activities)
      |> assign(:treaty_stats, treaty_stats)
    rescue
      error ->
        require Logger
        Logger.warning("Failed to load initial data for treaty #{treaty_id}: #{inspect(error)}")

        # Dados básicos de fallback
        socket
        |> assign(:treaty, %{treaty_code: treaty_id, status: "Indisponível", title: "Não carregado"})
        |> assign(:messages, [])
        |> assign(:has_more_messages, false)
        |> assign(:treaty_tags, [])
        |> assign(:presences, %{})
        |> assign(:users_online, [])
        |> assign(:message_count, 0)
        |> assign(:treaty_ratings, [])
        |> assign(:treaty_activities, [])
        |> assign(:treaty_stats, %{})
    end
  end

  defp handle_authenticated_user_actions(socket, authenticated_user, treaty_id) do
    case authenticated_user do
      %{id: user_id} ->
        App.Accounts.record_order_access(user_id, treaty_id)
        App.Notifications.mark_all_notifications_as_read(user_id)
        socket
      nil ->
        socket
    end
  end

  # --- Autenticação e Identidade do Usuário ---

  defp resolve_user_identity(socket, session) do
    case socket.assigns[:current_user] do
      nil -> extract_user_from_session_token(session)
      %{} = user -> extract_user_from_socket_assigns(user)
    end
  end

  defp extract_user_from_session_token(session) do
    case session["user_token"] do
      nil ->
        {ChatConfig.default_username(), nil}

      token when is_binary(token) ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, %{name: name} = user, _claims} when not is_nil(name) ->
            {name, user}

          {:ok, %{username: username} = user, _claims} when not is_nil(username) ->
            {username, user}

          {:ok, user, _claims} ->
            {ChatConfig.default_username(), user}

          {:error, _reason} ->
            {ChatConfig.default_username(), nil}
        end
    end
  end

  defp extract_user_from_socket_assigns(%{name: name} = user) when not is_nil(name) do
    {name, user}
  end

  defp extract_user_from_socket_assigns(%{username: username} = user) when not is_nil(username) do
    {username, user}
  end

  defp extract_user_from_socket_assigns(user) do
    default_name = ChatConfig.default_username()
    {default_name, user}
  end

  # --- Configuração de Comunicação em Tempo Real ---

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
      user_agent: get_connect_info(socket, :user_agent) || "Desconhecido"
    }

    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
        # Também rastrear no sistema de salas ativas
        if authenticated_user do
          case Process.whereis(App.ActiveRooms) do
            nil ->
              :ok
            _pid ->
              try do
                App.ActiveRooms.join_room(treaty_id, authenticated_user.id, user_name)
              rescue
                _e -> :ok
              catch
                :exit, _reason -> :ok
              end
          end
        end
      {:error, _reason} -> :ok
    end
  end

  defp get_user_id_for_presence(nil), do: "anonimo"
  defp get_user_id_for_presence(%{id: id}), do: id

  defp schedule_connection_status_update do
    Process.send_after(self(), :update_connection_status, 5000)
  end

  # --- Carregamento e Gerenciamento de Dados ---

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

  # Funções de segurança para evitar crashes
  defp safely_load_user_theme(nil), do: nil
  defp safely_load_user_theme(user) when is_map(user) do
    try do
      case App.Themes.get_user_theme(user.id) do
        {:ok, theme} -> theme
        {:error, _reason} -> nil
      end
    rescue
      _ -> nil
    end
  end
  defp safely_load_user_theme(_), do: nil

  defp safely_load_paginated_messages(treaty_id) when is_binary(treaty_id) do
    try do
      case App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.default_message_limit()) do
        {:ok, messages, has_more} -> {messages, has_more}
      end
    rescue
      _ -> {[], false}
    end
  end

  defp safely_get_treaty_tags(treaty_id) do
    try do
      Tags.get_treaty_tags(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_presences(topic) do
    try do
      Presence.list(topic)
    rescue
      _ -> %{}
    end
  end

  defp safely_get_treaty_ratings(nil), do: []
  defp safely_get_treaty_ratings(treaty_id) do
    try do
      App.Treaties.get_treaty_ratings(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_activities(nil, _limit), do: []
  defp safely_get_treaty_activities(treaty_id, limit) do
    try do
      App.Treaties.get_treaty_activities(treaty_id, limit)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_stats(nil), do: %{}
  defp safely_get_treaty_stats(treaty_id) do
    try do
      App.Treaties.get_treaty_stats(treaty_id)
    rescue
      _ -> %{}
    end
  end

  defp format_message_with_mentions(text) when is_binary(text) do
    # Substitui @username com menções destacadas
    text
    |> String.replace(~r/@(\w+)/, ~s(<span class="bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded-md text-xs font-medium">@\\1</span>))
    |> Phoenix.HTML.raw()
  end
  defp format_message_with_mentions(_), do: ""


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
    |> assign(:show_shortcuts_modal, false)
    |> assign(:show_shortcuts_tour, false)
    |> assign(:search_query, "")
    |> assign(:search_filters, %{
      date_from: nil,
      date_to: nil,
      user_filter: nil,
      content_type: "all"
    })
    |> assign(:search_results, [])
    |> assign(:search_active, false)
    |> assign(:show_close_modal, false)
    |> assign(:show_activities_modal, false)
    |> assign(:close_reason, "")
    |> assign(:resolution_notes, "")
    |> assign(:rating_value, "")
    |> assign(:can_close_treaty, false)
    |> assign(:rating_comment, "")
    |> update_can_close_treaty()
  end

  # --- Processamento de Mensagens ---

  @doc """
  Processa o envio de mensagens com validação e verificações de segurança.

  Valida o conteúdo da mensagem, lida com uploads de imagens e transmite
  a mensagem para todos os usuários conectados na sala de chat do pedido.
  """
  # --- Event Handlers ---
  # All handle_event/3 functions are grouped together for better organization
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

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :message_error, nil)}
  end

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
  def handle_event("update_message", %{"message" => message}, socket) do
    if connected?(socket) && String.length(message) > 0 do
      Phoenix.PubSub.broadcast(App.PubSub, socket.assigns.topic, {:typing_start, socket.assigns.current_user})
    end

    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def handle_event("typing", _params, socket) do
    if connected?(socket) do
      Phoenix.PubSub.broadcast(App.PubSub, socket.assigns.topic, {:typing_start, socket.assigns.current_user})
    end

    {:noreply, socket}
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

  @impl true
  def handle_event("close_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_sidebar, false)}
  end

  @impl true
  def handle_event("close_all_modals", _params, socket) do
    {:noreply,
      socket
      |> assign(:show_sidebar, false)
      |> assign(:show_search, false)
      |> assign(:show_tag_modal, false)
      |> assign(:modal_image_url, nil)
    }
  end

  @impl true
  def handle_event("show_shortcuts_help", _params, socket) do
    {:noreply, assign(socket, :show_shortcuts_modal, true)}
  end

  @impl true
  def handle_event("hide_shortcuts_help", _params, socket) do
    {:noreply, assign(socket, :show_shortcuts_modal, false)}
  end

  @impl true
  def handle_event("show_shortcuts_tour", _params, socket) do
    {:noreply, assign(socket, :show_shortcuts_tour, true)}
  end

  @impl true
  def handle_event("hide_shortcuts_tour", _params, socket) do
    {:noreply, assign(socket, :show_shortcuts_tour, false)}
  end

  def handle_event("focus_search", _params, socket), do: {:noreply, socket}
  def handle_event("blur_search", _params, socket), do: {:noreply, socket}
  def handle_event("stopPropagation", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("exit_chat", _params, socket) do
    # Navegar de volta para a tela de busca de tratativas
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    filtered_messages = apply_search_filters(socket.assigns.messages, query, socket.assigns.search_filters)

    {:noreply,
      socket
      |> assign(:search_query, query)
      |> assign(:search_results, filtered_messages)
      |> assign(:search_active, String.trim(query) != "")
    }
  end

  @impl true
  def handle_event("update_search_filters", %{"filters" => filters_json}, socket) do
    filters = Jason.decode!(filters_json)
    updated_filters = Map.merge(socket.assigns.search_filters, filters)
    filtered_messages = apply_search_filters(socket.assigns.messages, socket.assigns.search_query, updated_filters)

    {:noreply,
      socket
      |> assign(:search_filters, updated_filters)
      |> assign(:search_results, filtered_messages)
    }
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:search_active, false)
      |> assign(:search_filters, %{
        date_from: nil,
        date_to: nil,
        user_filter: nil,
        content_type: "all"
      })
    }
  end

  @impl true
  def handle_event("update_date_from", %{"value" => date_from}, socket) do
    updated_filters = Map.put(socket.assigns.search_filters, :date_from, parse_date(date_from))
    filtered_messages = apply_search_filters(socket.assigns.messages, socket.assigns.search_query, updated_filters)

    {:noreply,
      socket
      |> assign(:search_filters, updated_filters)
      |> assign(:search_results, filtered_messages)
    }
  end

  @impl true
  def handle_event("update_date_to", %{"value" => date_to}, socket) do
    updated_filters = Map.put(socket.assigns.search_filters, :date_to, parse_date(date_to))
    filtered_messages = apply_search_filters(socket.assigns.messages, socket.assigns.search_query, updated_filters)

    {:noreply,
      socket
      |> assign(:search_filters, updated_filters)
      |> assign(:search_results, filtered_messages)
    }
  end

  @impl true
  def handle_event("update_user_filter", %{"value" => user_filter}, socket) do
    updated_filters = Map.put(socket.assigns.search_filters, :user_filter, if(user_filter == "", do: nil, else: user_filter))
    filtered_messages = apply_search_filters(socket.assigns.messages, socket.assigns.search_query, updated_filters)

    {:noreply,
      socket
      |> assign(:search_filters, updated_filters)
      |> assign(:search_results, filtered_messages)
    }
  end

  @impl true
  def handle_event("update_content_type", %{"value" => content_type}, socket) do
    updated_filters = Map.put(socket.assigns.search_filters, :content_type, content_type)
    filtered_messages = apply_search_filters(socket.assigns.messages, socket.assigns.search_query, updated_filters)

    {:noreply,
      socket
      |> assign(:search_filters, updated_filters)
      |> assign(:search_results, filtered_messages)
    }
  end

  @impl true
  def handle_event("search_users", %{"query" => query}, socket) do
    matching_users = socket.assigns.users_online
    |> Enum.filter(fn username ->
      String.contains?(String.downcase(username), String.downcase(query))
    end)
    |> Enum.take(5) # Limit results to prevent UI overflow

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
    # O preview é exibido automaticamente pelo LiveView quando há entradas
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
    all_tags = Tags.list_tags(socket.assigns.user_object.store_id)

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
      # Mostrar todas as tags quando a consulta é muito curta para dar contexto aos usuários das opções disponíveis
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

        # Broadcast para todos os usuários no chat
        Phoenix.PubSub.broadcast(
          App.PubSub,
          socket.assigns.topic,
          {:treaty_tags_updated, treaty_tags}
        )

        {:noreply,
          socket
          |> assign(:treaty_tags, treaty_tags)
          |> assign(:show_tag_modal, false)
          |> assign(:tag_search_query, "")
          |> assign(:tag_search_results, [])
          |> push_event("show-toast", %{
            type: "success",
            title: "Tag adicionada!",
            message: "A tag foi adicionada com sucesso à tratativa.",
            duration: 3000
          })
        }
      {:error, _changeset} ->
        {:noreply,
          socket
          |> push_event("show-toast", %{
            type: "error",
            title: "Erro ao adicionar tag",
            message: "Não foi possível adicionar a tag. Tente novamente.",
            duration: 5000
          })
        }
    end
  end

  @impl true
  def handle_event("remove_tag_from_treaty", %{"tag_id" => tag_id}, socket) do
    case Tags.remove_tag_from_treaty(socket.assigns.treaty_id, tag_id) do
      {count, nil} when count > 0 ->
        treaty_tags = Tags.get_treaty_tags(socket.assigns.treaty_id)

        # Broadcast para todos os usuários no chat
        Phoenix.PubSub.broadcast(
          App.PubSub,
          socket.assigns.topic,
          {:treaty_tags_updated, treaty_tags}
        )

        {:noreply,
          socket
          |> assign(:treaty_tags, treaty_tags)
          |> push_event("show-toast", %{
            type: "success",
            title: "Tag removida!",
            message: "A tag foi removida com sucesso da tratativa.",
            duration: 3000
          })
        }
      _ ->
        {:noreply,
          socket
          |> push_event("show-toast", %{
            type: "error",
            title: "Erro ao remover tag",
            message: "Não foi possível remover a tag. Tente novamente.",
            duration: 5000
          })
        }
    end
  end

  @impl true
  def handle_event("show_close_modal", _params, socket) do
    {:noreply, assign(socket, :show_close_modal, true)}
  end

  @impl true
  def handle_event("hide_close_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:show_close_modal, false)
      |> assign(:close_reason, "")
      |> assign(:resolution_notes, "")
      |> assign(:rating_value, "")
      |> assign(:rating_comment, "")
    }
  end

  @impl true
  def handle_event("update_rating_value", %{"value" => value}, socket) do
    {:noreply, assign(socket, :rating_value, value)}
  end

  @impl true
  def handle_event("update_close_reason", %{"close_reason" => reason}, socket) do
    {:noreply, assign(socket, :close_reason, reason)}
  end

  @impl true
  def handle_event("update_resolution_notes", %{"resolution_notes" => notes}, socket) do
    {:noreply, assign(socket, :resolution_notes, notes)}
  end

  @impl true
  def handle_event("update_rating_comment", %{"rating_comment" => comment}, socket) do
    {:noreply, assign(socket, :rating_comment, comment)}
  end


  @impl true
  def handle_event("close_treaty", _params, socket) do
    # Ler valores dos campos do DOM
    reason = socket.assigns.close_reason || ""
    notes = socket.assigns.resolution_notes || ""
    rating = socket.assigns.rating_value || ""
    rating_comment = socket.assigns.rating_comment || ""
    case socket.assigns.user_object do
      nil ->
        {:noreply,
          socket
          |> push_event("show-toast", %{
            type: "error",
            title: "Erro",
            message: "Você precisa estar logado para encerrar tratativas.",
            duration: 5000
          })
        }

      user ->
        # Validar se uma avaliação foi selecionada
        if rating == "" do
          {:noreply,
            socket
            |> push_event("show-toast", %{
              type: "error",
              title: "Avaliação obrigatória",
              message: "Por favor, selecione uma avaliação antes de encerrar a tratativa.",
              duration: 5000
            })
          }
        else
          # Verificar permissão para encerrar a tratativa
          if App.Accounts.can_close_treaty?(user, socket.assigns.treaty) do
          close_attrs = %{
            close_reason: reason,
            resolution_notes: notes
          }

          case App.Treaties.close_treaty(socket.assigns.treaty, user.id, close_attrs) do
          {:ok, updated_treaty} ->
            # Adicionar avaliação automaticamente após o encerramento
            rating_attrs = %{
              rating: rating,
              comment: rating_comment,
              rated_at: DateTime.utc_now()
            }

            case App.Treaties.add_rating(updated_treaty.id, user.id, rating_attrs) do
              {:ok, _rating} ->
                # Recarregar dados da tratativa
                treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, 20)
                treaty_stats = App.Treaties.get_treaty_stats(updated_treaty.id)
                treaty_ratings = App.Treaties.get_treaty_ratings(updated_treaty.id)

                {:noreply,
                  socket
                  |> assign(:treaty, updated_treaty)
                  |> assign(:treaty_activities, treaty_activities)
                  |> assign(:treaty_stats, treaty_stats)
                  |> assign(:treaty_ratings, treaty_ratings)
                  |> assign(:show_close_modal, false)
                  |> assign(:close_reason, "")
                  |> assign(:resolution_notes, "")
                  |> assign(:rating_value, "")
                  |> assign(:rating_comment, "")
                  |> update_can_close_treaty()
                  |> push_event("show-toast", %{
                    type: "success",
                    title: "Tratativa encerrada e avaliada!",
                    message: "A tratativa foi encerrada e avaliada com sucesso.",
                    duration: 3000
                  })
                }

              {:error, _changeset} ->
                # Tratativa foi encerrada mas a avaliação falhou
                treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, 20)
                treaty_stats = App.Treaties.get_treaty_stats(updated_treaty.id)

                {:noreply,
                  socket
                  |> assign(:treaty, updated_treaty)
                  |> assign(:treaty_activities, treaty_activities)
                  |> assign(:treaty_stats, treaty_stats)
                  |> assign(:show_close_modal, false)
                  |> assign(:close_reason, "")
                  |> assign(:resolution_notes, "")
                  |> assign(:rating_value, "")
                  |> assign(:rating_comment, "")
                  |> update_can_close_treaty()
                  |> push_event("show-toast", %{
                    type: "warning",
                    title: "Tratativa encerrada!",
                    message: "A tratativa foi encerrada, mas houve um problema ao registrar a avaliação.",
                    duration: 5000
                  })
                }
            end

          {:error, _changeset} ->
            {:noreply,
              socket
              |> push_event("show-toast", %{
                type: "error",
                title: "Erro ao encerrar",
                message: "Não foi possível encerrar a tratativa. Tente novamente.",
                duration: 5000
              })
            }
          end
        else
          {:noreply,
            socket
            |> push_event("show-toast", %{
              type: "error",
              title: "Acesso negado",
              message: "Apenas o criador da tratativa ou administradores podem encerrá-la.",
              duration: 5000
            })
          }
        end
        end
    end
  end

  @impl true
  def handle_event("reopen_treaty", _params, socket) do
    case socket.assigns.user_object do
      nil ->
        {:noreply,
          socket
          |> push_event("show-toast", %{
            type: "error",
            title: "Erro",
            message: "Você precisa estar logado para reabrir tratativas.",
            duration: 5000
          })
        }

      user ->
        # Verificar permissão para reabrir a tratativa
        if App.Accounts.can_close_treaty?(user, socket.assigns.treaty) do
          case App.Treaties.reopen_treaty(socket.assigns.treaty, user.id) do
          {:ok, updated_treaty} ->
            # Recarregar dados da tratativa
            treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, 20)
            treaty_stats = App.Treaties.get_treaty_stats(updated_treaty.id)

            {:noreply,
              socket
              |> assign(:treaty, updated_treaty)
              |> assign(:treaty_activities, treaty_activities)
              |> assign(:treaty_stats, treaty_stats)
              |> update_can_close_treaty()
              |> push_event("show-toast", %{
                type: "success",
                title: "Tratativa reaberta!",
                message: "A tratativa foi reaberta com sucesso.",
                duration: 3000
              })
            }

          {:error, _changeset} ->
            {:noreply,
              socket
              |> push_event("show-toast", %{
                type: "error",
                title: "Erro ao reabrir",
                message: "Não foi possível reabrir a tratativa. Tente novamente.",
                duration: 5000
              })
            }
          end
        else
          {:noreply,
            socket
            |> push_event("show-toast", %{
              type: "error",
              title: "Acesso negado",
              message: "Apenas o criador da tratativa ou administradores podem reabri-la.",
              duration: 5000
            })
          }
        end
    end
  end



  @impl true
  def handle_event("show_activities_modal", _params, socket) do
    {:noreply, assign(socket, :show_activities_modal, true)}
  end

  @impl true
  def handle_event("hide_activities_modal", _params, socket) do
    {:noreply, assign(socket, :show_activities_modal, false)}
  end

  @impl true
  def handle_event("update_close_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :close_reason, reason)}
  end

  @impl true
  def handle_event("update_resolution_notes", %{"value" => notes}, socket) do
    {:noreply, assign(socket, :resolution_notes, notes)}
  end


  @impl true
  def handle_event("update_rating_comment", %{"value" => comment}, socket) do
    {:noreply, assign(socket, :rating_comment, comment)}
  end

  defp validate_message_input(socket, trimmed_text) do
    with {:ok, _} <- validate_message_not_empty(trimmed_text, socket),
         {:ok, _} <- validate_message_length(trimmed_text),
         {:ok, _} <- validate_connection(socket),
         {:ok, _} <- validate_treaty_status(socket) do
      {:ok, :valid}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_message_not_empty("", %{assigns: %{uploads: %{image: %{entries: []}}}}) do
    {:error, "Digite uma mensagem ou selecione uma imagem"}
  end
  defp validate_message_not_empty("", _socket), do: {:ok, :valid}
  defp validate_message_not_empty(_text, _socket), do: {:ok, :valid}

  defp validate_message_length(text) when is_binary(text) do
    max_length = ChatConfig.security_config()[:max_message_length]

    case byte_size(text) > max_length do
      true -> {:error, "Mensagem muito longa"}
      false -> {:ok, :valid}
    end
  end
  defp validate_message_length(_), do: {:ok, :valid}

  defp validate_connection(socket) do
    case connected?(socket) do
      true -> {:ok, :valid}
      false -> {:error, "Conexão perdida. Tente recarregar a página."}
    end
  end

  defp validate_treaty_status(socket) do
    case socket.assigns.treaty.status do
      "closed" -> {:error, "Esta tratativa está encerrada. Não é possível enviar mensagens."}
      _ -> {:ok, :valid}
    end
  end

  defp can_close_treaty?(socket) do
    case socket.assigns.user_object do
      nil -> false
      user -> App.Accounts.can_close_treaty?(user, socket.assigns.treaty)
    end
  end

  defp update_can_close_treaty(socket) do
    can_close = can_close_treaty?(socket)
    assign(socket, :can_close_treaty, can_close)
  end

  defp process_message_send(socket, trimmed_text) do
    file_info = handle_image_upload(socket)
    {user_id, _user_name} = get_user_info_for_message(socket)

    case App.Chat.send_message(socket.assigns.treaty_id, user_id, trimmed_text, file_info) do
      {:ok, _message} ->
        {:noreply,
          socket
          |> assign(:message, "")
          |> assign(:message_error, nil)
        }
      {:error, _changeset} ->
        {:noreply,
          socket
          |> assign(:message_error, "Erro ao enviar mensagem")
          |> push_event("show-toast", %{
            type: "error",
            title: "Erro ao enviar",
            message: "Não foi possível enviar a mensagem. Verifique sua conexão.",
            duration: 5000
          })
        }
    end
  end

  defp handle_image_upload(socket) do
    entries = socket.assigns.uploads.image.entries

    case entries do
      [] -> nil
      [_entry | _] ->
        # Processar arquivos e enviar para Oban
        consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
          # Copiar arquivo para local temporário
          temp_path = create_temp_file(path, entry.client_name)

          # Enviar job para Oban (será processado após a mensagem ser criada)
          {:ok, %{
            temp_path: temp_path,
            original_filename: entry.client_name,
            file_size: entry.client_size,
            mime_type: entry.client_type,
            pending_upload: true
          }}
        end)
        |> Enum.filter(&(&1 != nil))
    end
  end

  # Cria arquivo temporário para processamento assíncrono
  defp create_temp_file(source_path, original_name) do
    # Criar diretório temporário se não existir
    temp_dir = Path.join(System.tmp_dir(), "juruconnect_uploads")
    File.mkdir_p!(temp_dir)

    # Gerar nome único para arquivo temporário
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    extension = Path.extname(original_name)
    temp_filename = "upload_#{timestamp}_#{unique_id}#{extension}"
    temp_path = Path.join(temp_dir, temp_filename)

    # Copiar arquivo para local temporário
    case File.cp(source_path, temp_path) do
      :ok -> temp_path
      {:error, _reason} ->
        # Fallback: usar o arquivo original se não conseguir copiar
        source_path
    end
  end

  defp get_user_info_for_message(%{assigns: %{user_object: nil, current_user: current_user}}) do
    {nil, current_user}
  end
  defp get_user_info_for_message(%{assigns: %{user_object: %{id: id, name: name}, current_user: _}}) when not is_nil(name) do
    {id, name}
  end
  defp get_user_info_for_message(%{assigns: %{user_object: %{id: id, username: username}, current_user: _}}) when not is_nil(username) do
    {id, username}
  end
  defp get_user_info_for_message(%{assigns: %{user_object: %{id: id}, current_user: current_user}}) do
    {id, current_user}
  end








  @impl true
  def handle_info({:new_message, msg}, socket) do
    try do
      # Validação de estrutura da mensagem
      if msg && Map.get(msg, :treaty_id) == socket.assigns.treaty_id do
        socket = socket
        |> update(:messages, fn current_messages ->
          current_messages ++ [msg]
        end)
        |> update(:message_count, fn count -> count + 1 end)
        |> push_event("scroll-to-bottom", %{})

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    rescue
      error ->
        require Logger
        Logger.warning("Error handling new message: #{inspect(error)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:upload_complete, %{message_id: message_id, file_url: file_url}}, socket) do
    try do
      # Atualizar mensagem com anexo quando upload for concluído
      updated_socket = socket
      |> update(:messages, fn messages ->
        Enum.map(messages, fn msg ->
          if msg.id == message_id do
            # Safely recarregar anexos da mensagem
            try do
              attachments = App.Chat.get_message_attachments(message_id)
              %{msg | attachments: attachments}
            rescue
              _ -> msg  # Se falhar, mantém mensagem sem anexos
            end
          else
            msg
          end
        end)
      end)
      |> push_event("upload-complete", %{message_id: message_id, file_url: file_url})

      {:noreply, updated_socket}
    rescue
      error ->
        require Logger
        Logger.warning("Error handling upload complete: #{inspect(error)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:wallpaper_applied, %{wallpaper_url: url}}, socket) do
    try do
      # Safely recarregar tema do usuário quando papel de parede for aplicado
      user_theme = if socket.assigns.user_object do
        safely_load_user_theme(socket.assigns.user_object)
      else
        nil
      end

      socket = socket
      |> assign(:user_theme, user_theme)
      |> push_event("theme-updated", %{wallpaper_url: url})

      {:noreply, socket}
    rescue
      error ->
        require Logger
        Logger.warning("Error handling wallpaper applied: #{inspect(error)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:notification, :new_message, notification_data}, socket) do
    # Mostrar notificação apenas se o usuário não estiver no chat atual
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
    # Sempre mostrar notificações de menção
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

  @impl true
  def handle_info({:treaty_tags_updated, treaty_tags}, socket) do
    {:noreply, assign(socket, :treaty_tags, treaty_tags)}
  end

  @doc """
  Atualiza informações de presença do usuário quando usuários entram ou saem do chat.

  Mantém visibilidade em tempo real de participantes ativos para melhorar
  consciência de colaboração e contexto de comunicação.
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

    # Remover usuário das salas ativas quando desconectado
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

    # Continuar monitorando enquanto conectado para fornecer atualizações de status em tempo real
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
    # Remover usuário das salas ativas quando o LiveView termina
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
         phx-hook="ChatCompositeHook"
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
            <!-- Botão para abrir sidebar no mobile -->
            <button phx-click="toggle_sidebar" class="lg:hidden p-2 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                    aria-label="Abrir sidebar com tags e usuários online"
                    title="Tags e usuários online">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
              </svg>
            </button>
            <!-- Botão de atividades/tracking -->
            <button phx-click="show_activities_modal" class="p-2 text-gray-500 hover:text-indigo-600 hover:bg-indigo-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                    aria-label="Ver atividades da tratativa"
                    title="Histórico de atividades">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </button>


            <!-- Botão de encerrar/reabrir tratativa -->
            <%= if @can_close_treaty do %>
              <%= if @treaty.status == "closed" do %>
                <button phx-click="reopen_treaty" class="p-2 text-gray-500 hover:text-green-600 hover:bg-green-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-green-500 focus:ring-offset-2"
                        aria-label="Reabrir tratativa"
                        title="Reabrir tratativa">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                </button>
              <% else %>
                <button phx-click="show_close_modal" class="p-2 text-gray-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
                        aria-label="Encerrar tratativa"
                        title="Encerrar tratativa">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              <% end %>
            <% end %>

            <button phx-click="toggle_search" class="p-2 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                    aria-label="Buscar mensagens"
                    title="Buscar mensagens (Ctrl+K)">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
            </button>
            <button phx-click="show_shortcuts_help" class="p-2 text-gray-500 hover:text-purple-600 hover:bg-purple-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-purple-500 focus:ring-offset-2"
                    aria-label="Mostrar atalhos de teclado"
                    title="Atalhos de teclado (Ctrl+/)">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </button>
            <button
              phx-click="exit_chat"
              class="p-2 text-gray-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
              title="Sair do chat e voltar para busca de tratativas"
              aria-label="Sair do chat"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
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
          <div class="mx-2 sm:mx-3 mt-2 p-4 bg-gradient-to-r from-blue-50 to-indigo-50 border border-blue-200 rounded-xl shadow-sm">
            <!-- Search Input -->
            <div class="flex items-center space-x-2 mb-3">
              <svg class="w-5 h-5 text-blue-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
              <input
                type="text"
                placeholder="Buscar nas mensagens..."
                value={@search_query}
                class="flex-1 px-3 py-2 text-sm border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200"
                phx-keyup="search_messages"
                phx-debounce="300"
                aria-label="Buscar mensagens"
              />
              <%= if @search_active do %>
                <button phx-click="clear_search" class="text-gray-500 hover:text-gray-700 p-2 hover:bg-gray-100 rounded-lg transition-colors" aria-label="Limpar busca">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              <% end %>
              <button phx-click="toggle_search" class="text-blue-500 hover:text-blue-700 p-2 hover:bg-blue-100 rounded-lg transition-colors" aria-label="Fechar busca">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>

            <!-- Advanced Filters -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
              <!-- Date Range Filter -->
              <div class="space-y-1">
                <label class="text-xs font-medium text-gray-700">Período</label>
                <div class="flex space-x-1">
                  <input
                    type="date"
                    class="flex-1 px-2 py-1.5 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                    phx-change="update_date_from"
                    placeholder="De"
                  />
                  <input
                    type="date"
                    class="flex-1 px-2 py-1.5 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                    phx-change="update_date_to"
                    placeholder="Até"
                  />
          </div>
              </div>

              <!-- User Filter -->
              <div class="space-y-1">
                <label class="text-xs font-medium text-gray-700">Usuário</label>
                <select
                  class="w-full px-2 py-1.5 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                  phx-change="update_user_filter"
                >
                  <option value="">Todos os usuários</option>
                  <%= for user <- @users_online do %>
                    <option value={user}><%= user %></option>
                  <% end %>
                </select>
              </div>

              <!-- Content Type Filter -->
              <div class="space-y-1">
                <label class="text-xs font-medium text-gray-700">Tipo de conteúdo</label>
                <select
                  class="w-full px-2 py-1.5 text-xs border border-gray-300 rounded focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                  phx-change="update_content_type"
                >
                  <option value="all">Todos</option>
                  <option value="text">Apenas texto</option>
                  <option value="images">Com imagens</option>
                </select>
              </div>
            </div>

            <!-- Search Results Summary -->
            <%= if @search_active do %>
              <div class="mt-3 pt-3 border-t border-blue-200">
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-2">
                    <svg class="w-4 h-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <span class="text-sm font-medium text-blue-800">
                      <%= length(@search_results) %> resultado<%= if length(@search_results) != 1, do: "s", else: "" %> encontrado<%= if length(@search_results) != 1, do: "s", else: "" %>
                    </span>
                  </div>
                  <button phx-click="clear_search" class="text-xs text-blue-600 hover:text-blue-800 font-medium">
                    Limpar filtros
                  </button>
                </div>
              </div>
            <% end %>
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
                class={"px-3 py-1.5 text-xs text-gray-600 bg-white border border-gray-200 rounded hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-1 shadow-sm hover:shadow-md transform hover:-translate-y-0.5 " <>
                       if(@loading_messages, do: "btn-loading", else: "")}>
                <%= if @loading_messages do %>
                  <svg class="w-3 h-3 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  <span>Carregando mensagens...</span>
                <% else %>
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"></path>
                  </svg>
                  <span>Carregar anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <%= if @search_active && Enum.empty?(@search_results) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-6 animate-fade-in">
              <div class="w-12 h-12 bg-gradient-to-br from-blue-100 to-indigo-100 rounded-full flex items-center justify-center mb-3 shadow-sm">
                <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                </svg>
              </div>
              <h2 class="text-sm font-semibold text-gray-900 mb-2">Nenhum resultado encontrado</h2>
              <p class="text-xs text-gray-600 max-w-md">Tente ajustar os filtros ou usar termos de busca diferentes.</p>
            </div>
          <% else %>
            <%= if @search_active do %>
              <%= for {message, index} <- Enum.with_index(@search_results) do %>
                <%= render_message(message, index, @search_results, @user_object) %>
              <% end %>
            <% else %>
          <!-- Banner de tratativa encerrada -->
          <%= if @treaty.status == "closed" do %>
            <div class="bg-amber-50 border-l-4 border-amber-400 p-4 mb-4 rounded-r-lg shadow-sm">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg class="h-5 w-5 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
                  </svg>
                </div>
                <div class="ml-3">
                  <p class="text-sm text-amber-700">
                    <strong>Esta tratativa está encerrada.</strong> Não é possível enviar novas mensagens.
                    <%= if @treaty.close_reason do %>
                      Motivo: <%= @treaty.close_reason %>.
                    <% end %>
                  </p>
                </div>
              </div>
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
                  <%= render_message(message, index, @messages, @user_object) %>
              <% end %>
                  <% end %>
                        <% end %>
                      <% end %>
                    </div>

          <!-- Sidebar com usuários online e tags -->
          <div class={"w-64 bg-white border-l border-gray-200 overflow-y-auto transition-transform duration-300 ease-in-out " <>
                if(@show_sidebar, do: "translate-x-0", else: "translate-x-full") <>
                " lg:translate-x-0 lg:block " <>
                if(@show_sidebar, do: "fixed inset-y-0 right-0 z-30", else: "hidden lg:block")}
                role="complementary"
                aria-label="Sidebar com tags e usuários online">
            <!-- Header da sidebar com botão de fechar no mobile -->
            <div class="lg:hidden flex items-center justify-between p-4 border-b border-gray-200 bg-gray-50">
              <h2 class="text-lg font-semibold text-gray-900">Menu</h2>
              <button phx-click="close_sidebar"
                      class="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-all duration-200 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                      aria-label="Fechar menu">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                      </svg>
              </button>
                </div>


            <!-- Seção de Tags -->
            <div class="p-4 border-b border-gray-200">
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-sm font-semibold text-gray-900">Tags</h3>
                <button phx-click="show_tag_modal"
                        class="p-2 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
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
                              class="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-all duration-200 focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
                              title="Remover tag"
                              aria-label={"Remover tag #{tag.name}"}>
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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

          <form phx-submit="send_message" phx-drop-target={if @treaty.status != "closed", do: @uploads.image.ref, else: nil} class="flex items-end space-x-2 sm:space-x-3 transition-all duration-200" role="form" aria-label="Enviar mensagem">
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>
              <!-- Drag and drop overlay -->
              <div class="fixed inset-0 bg-gradient-to-br from-blue-500/30 via-blue-400/20 to-blue-600/30 backdrop-blur-md flex items-center justify-center opacity-0 pointer-events-none transition-all duration-300 z-50" id="drag-overlay">
                <div class="bg-white/95 backdrop-blur-lg rounded-3xl p-8 shadow-2xl border border-blue-200/50 transform scale-95 transition-all duration-300 max-w-sm mx-4" id="drag-content">
                  <div class="text-center">
                    <!-- Ícone animado -->
                    <div class="relative mb-6">
                      <div class="w-20 h-20 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center mx-auto shadow-xl">
                        <svg class="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
                        </svg>
                      </div>
                      <!-- Círculos animados -->
                      <div class="absolute inset-0 w-20 h-20 mx-auto">
                        <div class="absolute inset-0 border-4 border-blue-300/60 rounded-full animate-ping"></div>
                        <div class="absolute inset-2 border-2 border-blue-400/60 rounded-full animate-ping" style="animation-delay: 0.5s"></div>
                        <div class="absolute inset-4 border border-blue-500/60 rounded-full animate-ping" style="animation-delay: 1s"></div>
                      </div>
                    </div>

                    <h3 class="text-xl font-bold text-gray-800 mb-2">Solte a imagem aqui</h3>
                    <p class="text-sm text-gray-600 mb-4">JPG, PNG, GIF até 5MB</p>

                    <!-- Barra de progresso animada -->
                    <div class="w-32 h-1 bg-gray-200 rounded-full mx-auto overflow-hidden">
                      <div class="h-full bg-gradient-to-r from-blue-500 to-blue-600 rounded-full animate-pulse"></div>
                    </div>

                    <!-- Indicador de área de drop -->
                    <div class="mt-4 flex items-center justify-center space-x-2 text-blue-600">
                      <div class="w-2 h-2 bg-blue-500 rounded-full animate-bounce"></div>
                      <div class="w-2 h-2 bg-blue-500 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                      <div class="w-2 h-2 bg-blue-500 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                    </div>
                  </div>
                </div>
              </div>
              <!-- Preview da imagem -->
              <%= if @uploads[:image] && @uploads.image.entries != [] do %>
                <div class="mb-1 flex items-center space-x-1">
                  <%= for entry <- @uploads.image.entries do %>
                    <div class="relative inline-block mr-1 mb-1">
                      <!-- Preview da imagem -->
                      <.live_img_preview entry={entry} class="w-20 h-20 object-cover rounded-lg border border-gray-200 shadow-md hover:shadow-lg transition-shadow duration-200" />

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
                              class="absolute top-0 right-0 bg-white/90 rounded-full p-1 text-red-500 hover:text-red-700 hover:bg-white transition-all duration-200 focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
                              title="Remover imagem"
                              aria-label="Remover imagem">
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
                placeholder="Digite uma mensagem ou arraste uma imagem aqui..."
                class="w-full px-4 py-3 pr-12 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-blue-300 hover:shadow-md text-base focus:outline-none disabled:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-60"
                autocomplete="off"
                maxlength={ChatConfig.security_config()[:max_message_length]}
                disabled={not @connected or @treaty.status == "closed"}
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
              <label for="image-upload" class={"absolute right-3 top-1/2 transform -translate-y-1/2 p-2 text-gray-400 hover:text-blue-600 transition-all duration-200 rounded-lg hover:bg-blue-50 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 " <> if(@treaty.status == "closed", do: "cursor-not-allowed opacity-50", else: "cursor-pointer")} aria-label="Anexar arquivo" title="Anexar arquivo">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                </svg>
                <.live_file_input upload={@uploads.image} id="image-upload" class="hidden" phx-change="validate" phx-upload="upload" disabled={@treaty.status == "closed"} />
                <!-- Input separado para drag & drop -->
                <input
                  id="drag-drop-input"
                  type="file"
                  accept="image/*"
                  class="hidden"
                  phx-hook="ImageUploadHook"
                  multiple={true}
                  disabled={@treaty.status == "closed"}
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={String.trim(@message) == "" && @uploads.image.entries == [] or @treaty.status == "closed"}
              class="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-700 text-white rounded-xl hover:from-blue-700 hover:to-blue-800 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-2 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed phx-submit-loading:opacity-75 text-base min-w-[60px]"
              aria-label="Enviar mensagem"
              aria-describedby="send-button-help"
              title="Enviar mensagem">
              <span class="hidden sm:inline">Enviar</span>
              <span class="sm:hidden">→</span>
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
              </svg>
            </button>
            <div id="send-button-help" class="sr-only">
              Botão para enviar mensagem ou imagem. Disponível quando há texto ou imagem para enviar.
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

    <!-- Modal de Atalhos de Teclado -->
    <%= if @show_shortcuts_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" phx-click="hide_shortcuts_help">
        <div class="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[80vh] overflow-hidden" phx-click="stopPropagation">
          <!-- Header do modal -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200 bg-gradient-to-r from-purple-50 to-blue-50">
            <div class="flex items-center space-x-3">
              <div class="w-10 h-10 bg-gradient-to-br from-purple-500 to-blue-600 rounded-xl flex items-center justify-center">
                <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
              </div>
              <div>
                <h3 class="text-xl font-bold text-gray-900">Atalhos de Teclado</h3>
                <p class="text-sm text-gray-600">Acelere seu trabalho com estes atalhos</p>
              </div>
            </div>
            <button phx-click="hide_shortcuts_help" class="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-all duration-200 focus:ring-2 focus:ring-purple-500 focus:ring-offset-2">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Conteúdo do modal -->
          <div class="p-6 overflow-y-auto max-h-[60vh]">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <!-- Navegação -->
              <div class="space-y-4">
                <h4 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                  </svg>
                  Navegação
                </h4>
                <div class="space-y-3">
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Abrir busca</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">Ctrl+K</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Fechar modais</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">ESC</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Mostrar atalhos</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">Ctrl+/</kbd>
                  </div>
                </div>
              </div>

              <!-- Mensagens -->
              <div class="space-y-4">
                <h4 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                  </svg>
                  Mensagens
                </h4>
                <div class="space-y-3">
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Enviar mensagem</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">Ctrl+Enter</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Navegar mensagens</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">↑↓</kbd>
                  </div>
                </div>
              </div>

              <!-- Ações Rápidas -->
              <div class="space-y-4">
                <h4 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                  </svg>
                  Ações Rápidas
                </h4>
                <div class="space-y-3">
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Focar input</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">1</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Toggle sidebar</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">2</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Gerenciar tags</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">3</kbd>
                  </div>
                  <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <span class="text-sm font-medium text-gray-700">Sair do chat</span>
                    <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">4</kbd>
                  </div>
                </div>
              </div>

              <!-- Dicas -->
              <div class="space-y-4">
                <h4 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
                  </svg>
                  Dicas
                </h4>
                <div class="space-y-3">
                  <div class="p-3 bg-blue-50 rounded-lg border border-blue-200">
                    <p class="text-sm text-blue-800">
                      <strong>💡 Dica:</strong> Use <kbd class="px-1 py-0.5 bg-blue-200 text-blue-800 rounded text-xs font-mono">Ctrl+K</kbd> para buscar rapidamente em qualquer lugar do chat.
                    </p>
                  </div>
                  <div class="p-3 bg-green-50 rounded-lg border border-green-200">
                    <p class="text-sm text-green-800">
                      <strong>⚡ Produtividade:</strong> Os atalhos funcionam mesmo quando você não está focando nos elementos da interface.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Rodapé -->
          <div class="flex items-center justify-between p-6 border-t border-gray-200 bg-gray-50">
            <p class="text-sm text-gray-600">
              💡 Pressione <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">Ctrl+/</kbd> a qualquer momento para mostrar esta ajuda
            </p>
            <button phx-click="hide_shortcuts_help" class="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors focus:ring-2 focus:ring-purple-500 focus:ring-offset-2">
              Entendi!
            </button>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Tour de Boas-vindas para Shortcuts -->
    <%= if @show_shortcuts_tour do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" phx-click="hide_shortcuts_tour">
        <div class="bg-white rounded-2xl shadow-2xl max-w-md w-full" phx-click="stopPropagation">
          <div class="p-6 text-center">
            <div class="w-16 h-16 bg-gradient-to-br from-purple-500 to-blue-600 rounded-full flex items-center justify-center mx-auto mb-4">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
              </svg>
            </div>
            <h3 class="text-xl font-bold text-gray-900 mb-2">🚀 Atalhos de Teclado Ativados!</h3>
            <p class="text-gray-600 mb-4">
              Agora você pode usar atalhos para ser mais produtivo no chat.
              Experimente <kbd class="px-2 py-1 bg-gray-200 text-gray-700 rounded text-xs font-mono">Ctrl+K</kbd> para buscar!
            </p>
            <div class="flex space-x-3">
              <button phx-click="hide_shortcuts_tour" class="flex-1 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors">
                Pular
              </button>
              <button phx-click="show_shortcuts_help" class="flex-1 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors">
                Ver Todos
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Modal de Encerrar Tratativa -->
    <%= if @show_close_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" phx-click="hide_close_modal">
        <div id="close-modal" class="bg-white rounded-2xl shadow-2xl max-w-md w-full" phx-click="stopPropagation" phx-hook="RatingHook">
          <!-- Header do modal -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <h3 class="text-xl font-bold text-gray-900">Encerrar e Avaliar Tratativa</h3>
            <button phx-click="hide_close_modal" class="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-all duration-200">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Conteúdo do modal -->
          <div class="p-6 space-y-6">
            <!-- Seção de Encerramento -->
            <div class="space-y-4">
              <h4 class="text-lg font-semibold text-gray-900 border-b border-gray-200 pb-2">Encerramento</h4>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Motivo do encerramento</label>
                <select phx-change="update_close_reason" phx-value-field="close_reason" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-red-500" required>
                  <option value="">Selecione um motivo</option>
                  <option value="resolved">Resolvido</option>
                  <option value="cancelled">Cancelado</option>
                  <option value="duplicate">Duplicado</option>
                  <option value="invalid">Inválido</option>
                  <option value="other">Outro</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Notas de resolução</label>
                <textarea phx-change="update_resolution_notes" phx-value-field="resolution_notes" rows="3" placeholder="Descreva como a tratativa foi resolvida..." class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-red-500"></textarea>
              </div>
            </div>

            <!-- Seção de Avaliação -->
            <div class="space-y-4">
              <h4 class="text-lg font-semibold text-gray-900 border-b border-gray-200 pb-2">Avaliação</h4>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Como você avalia esta tratativa? <span class="text-red-500">*</span></label>
                <div class="grid grid-cols-2 gap-2">
                    <button type="button"
                            data-rating="péssimo"
                            class={"px-3 py-2 text-sm font-medium rounded-lg border transition-colors #{if @rating_value == "péssimo", do: "bg-blue-600 text-white border-blue-600", else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"}"}>
                      Péssimo
                    </button>
                    <button type="button"
                            data-rating="ruim"
                            class={"px-3 py-2 text-sm font-medium rounded-lg border transition-colors #{if @rating_value == "ruim", do: "bg-blue-600 text-white border-blue-600", else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"}"}>
                      Ruim
                    </button>
                    <button type="button"
                            data-rating="bom"
                            class={"px-3 py-2 text-sm font-medium rounded-lg border transition-colors #{if @rating_value == "bom", do: "bg-blue-600 text-white border-blue-600", else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"}"}>
                      Bom
                    </button>
                    <button type="button"
                            data-rating="excelente"
                            class={"px-3 py-2 text-sm font-medium rounded-lg border transition-colors #{if @rating_value == "excelente", do: "bg-blue-600 text-white border-blue-600", else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"}"}>
                      Excelente
                    </button>
                </div>
                <%= if @rating_value == "" do %>
                  <p class="text-red-500 text-xs mt-1">Por favor, selecione uma avaliação</p>
                <% end %>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Comentário (opcional)</label>
                <textarea phx-change="update_rating_comment" phx-value-field="rating_comment" rows="2" placeholder="Deixe um comentário sobre sua experiência..." class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-yellow-500 focus:border-yellow-500"></textarea>
              </div>
            </div>

            <div class="flex space-x-3 pt-4">
              <button type="button" phx-click="hide_close_modal" class="flex-1 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors">
                Cancelar
              </button>
              <button type="button" phx-click="close_treaty" class="flex-1 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors">
                Encerrar e Avaliar
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>


    <!-- Modal de Atividades -->
    <%= if @show_activities_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" phx-click="hide_activities_modal">
        <div class="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[80vh] overflow-hidden" phx-click="stopPropagation">
          <!-- Header do modal -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <h3 class="text-xl font-bold text-gray-900">Histórico de Atividades</h3>
            <button phx-click="hide_activities_modal" class="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-lg transition-all duration-200">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>

          <!-- Conteúdo do modal -->
          <div class="p-6 overflow-y-auto max-h-[60vh]">
            <%= if Enum.empty?(@treaty_activities) do %>
              <div class="text-center py-8">
                <div class="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                  <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                </div>
                <p class="text-sm text-gray-500">Nenhuma atividade registrada</p>
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for activity <- @treaty_activities do %>
                  <div class="flex items-start space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center flex-shrink-0">
                      <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center justify-between">
                        <p class="text-sm font-medium text-gray-900"><%= activity.description %></p>
                        <span class="text-xs text-gray-500"><%= format_time(activity.activity_at) %></span>
                      </div>
                      <%= if activity.user do %>
                        <p class="text-xs text-gray-500">por <%= activity.user.name || activity.user.username %></p>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Funções Utilitárias ---

  defp apply_search_filters(messages, query, filters) do
    messages
    |> filter_by_text(query)
    |> filter_by_date_range(filters.date_from, filters.date_to)
    |> filter_by_user(filters.user_filter)
    |> filter_by_content_type(filters.content_type)
  end

  defp filter_by_text(messages, query) when query == "" or is_nil(query), do: messages
  defp filter_by_text(messages, query) do
    query_lower = String.downcase(query)
    Enum.filter(messages, fn message ->
      String.contains?(String.downcase(message.text || ""), query_lower)
    end)
  end

  defp filter_by_date_range(messages, nil, nil), do: messages
  defp filter_by_date_range(messages, date_from, date_to) do
    Enum.filter(messages, fn message ->
      message_date = message.inserted_at || message.timestamp
      case message_date do
        nil -> false
        dt ->
          date_from_ok = if date_from, do: DateTime.compare(dt, date_from) != :lt, else: true
          date_to_ok = if date_to, do: DateTime.compare(dt, date_to) != :gt, else: true
          date_from_ok && date_to_ok
      end
    end)
  end

  defp filter_by_user(messages, nil), do: messages
  defp filter_by_user(messages, user_filter) do
    Enum.filter(messages, fn message ->
      String.contains?(String.downcase(message.sender_name || ""), String.downcase(user_filter))
    end)
  end

  defp filter_by_content_type(messages, "all"), do: messages
  defp filter_by_content_type(messages, "text") do
    Enum.filter(messages, fn message ->
      is_nil(message.attachments) || length(message.attachments) == 0
    end)
  end
  defp filter_by_content_type(messages, "images") do
    Enum.filter(messages, fn message ->
      message.attachments &&
      Enum.any?(message.attachments, fn att -> att.file_type == "image" end)
    end)
  end

  defp parse_date(""), do: nil
  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      {:error, _} -> nil
    end
  end
  defp parse_date(_), do: nil

  defp extract_users_from_presences(presences) when is_map(presences) do
    presences
    |> Map.values()
    |> Enum.flat_map(&extract_names_from_metas/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
  defp extract_users_from_presences(_), do: []

  defp extract_names_from_metas(%{metas: metas}) when is_list(metas) do
    Enum.map(metas, fn %{name: name} when is_binary(name) -> name end)
  end
  defp extract_names_from_metas(_), do: []

  defp load_older_messages_async(socket) do
    treaty_id = socket.assigns.treaty_id
    current_count = length(socket.assigns.messages)

    Task.start(fn ->
      with {:ok, older_messages, has_more} <- App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.pagination_config()[:default_limit], current_count) do
        send(self(), {:older_messages_loaded, older_messages, has_more})
      else
        {:error, _reason} ->
          send(self(), {:older_messages_loaded, [], false})
      end
    end)

    socket
  end

  # --- Auxiliares de Formatação e Exibição da Interface ---

  defp get_user_initial(user) when is_binary(user) and byte_size(user) > 0 do
    user |> String.first() |> String.upcase()
  end
  defp get_user_initial(_), do: "U"

  defp get_status_class(status) do
    base_classes = "px-2.5 py-1 text-xs font-semibold rounded-full border shadow-sm transition-all duration-200"

    case status do
      "active" -> "#{base_classes} bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100"
      "inactive" -> "#{base_classes} bg-amber-50 text-amber-700 border-amber-200 hover:bg-amber-100"
      "cancelled" -> "#{base_classes} bg-red-50 text-red-700 border-red-200 hover:bg-red-100"
      "completed" -> "#{base_classes} bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100"
      "closed" -> "#{base_classes} bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
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
      %DateTime{} = dt -> format_relative_date(dt)
      _ -> "Data não disponível"
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

  defp render_message(message, index, message_list, user_object) do
    is_current_user = case user_object do
      nil -> false
      user -> user.id == message.sender_id
    end

    previous_message = if index > 0, do: Enum.at(message_list, index - 1), else: nil
    show_date_separator = should_show_date_separator(message, previous_message)

    assigns = %{
      message: message,
      index: index,
      message_list: message_list,
      user_object: user_object,
      is_current_user: is_current_user,
      show_date_separator: show_date_separator
    }

    ~H"""
    <%= if @show_date_separator do %>
      <!-- Separador de Data -->
      <div class="flex items-center justify-center my-4">
        <div class="bg-gray-100 text-gray-600 text-xs font-medium px-3 py-1 rounded-full shadow-sm border border-gray-200">
          <%= format_date_separator(@message.timestamp || @message.inserted_at) %>
        </div>
      </div>
    <% end %>
    <div class={"flex mb-3 animate-slide-in " <> if(@is_current_user, do: "justify-end", else: "justify-start")}
         role="article"
         aria-label={"Mensagem de " <> @message.sender_name}>
      <div class={
        "relative max-w-[90%] sm:max-w-[85%] md:max-w-md lg:max-w-lg xl:max-w-xl px-3 sm:px-4 py-2.5 sm:py-3 rounded-xl shadow-md transition-all duration-200 hover:shadow-lg " <>
        if(@is_current_user,
          do: "bg-gradient-to-br from-blue-500 to-blue-600 text-white rounded-br-lg",
          else: "bg-white text-gray-900 rounded-bl-lg border border-gray-200 shadow-sm hover:border-gray-300")
      }>
        <%= if not @is_current_user do %>
          <div class="text-sm font-semibold text-gray-700 mb-1"><%= @message.sender_name %></div>
        <% end %>
        <div class="text-sm break-words leading-relaxed"><%= format_message_with_mentions(@message.text) %></div>
        <%= if @message.attachments && length(@message.attachments) > 0 do %>
          <div class="mt-2 space-y-2">
            <%= for attachment <- @message.attachments do %>
              <%= if attachment.file_type == "image" do %>
                <img src={attachment.file_url}
                     class="w-32 h-32 sm:w-40 sm:h-40 object-cover rounded-lg cursor-pointer hover:scale-105 transition-all duration-300 shadow-md hover:shadow-lg"
                     phx-click="show_image"
                     phx-value-url={attachment.file_url}
                     alt={attachment.original_filename} />
              <% end %>
            <% end %>
          </div>
        <% end %>
        <div class="flex items-center justify-end mt-1 space-x-1">
          <span class={"text-xs " <> if(@is_current_user, do: "text-white/70", else: "text-gray-400")}><%= format_time(@message.inserted_at) %></span>
          <%= if @is_current_user do %>
            <svg class="w-2.5 h-2.5 text-white/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Carrega o tema do usuário
  defp load_user_theme(nil), do: nil
  defp load_user_theme(user) when is_map(user) do
    case App.Themes.get_user_theme(user.id) do
      {:ok, theme} -> theme
      {:error, _reason} -> nil
    end
  end
  defp load_user_theme(_), do: nil
end
