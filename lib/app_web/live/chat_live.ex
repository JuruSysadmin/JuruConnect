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
  alias AppWeb.ChatConfig
  alias AppWeb.ChatLive.AuthHelper
  alias AppWeb.ChatLive.TagManager
  alias App.DateTimeHelper

  defstruct [:filename, :original_filename, :file_size, :mime_type, :file_url]

  @doc """
  Hook de autenticação que valida tokens de sessão do usuário.

  Delega a responsabilidade de autenticação para o AuthHelper.
  """
  def on_mount(:default, params, session, socket) do
    AuthHelper.on_mount(:default, params, session, socket)
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
      socket = socket
      |> initialize_chat_session(treaty_id, session)

      {:ok, socket}
    rescue
      error ->
        require Logger
        Logger.error("LiveView mount error for treaty #{treaty_id}: #{inspect(error)}")
        {:ok, create_error_socket(socket, treaty_id, session)}
    end
  end

  defp initialize_chat_session(socket, treaty_id, session) do
    topic = "treaty:#{treaty_id}"
    {current_user_name, authenticated_user} = AuthHelper.resolve_user_identity(socket, session)
    is_connected = connected?(socket)
    connection_status = if is_connected, do: "Conectado", else: "Desconectado"

    socket
    |> setup_connection_if_connected(topic, current_user_name, authenticated_user, treaty_id)
    |> load_initial_data(treaty_id, topic, authenticated_user)
    |> AuthHelper.handle_authenticated_user_actions(authenticated_user, treaty_id)
    |> assign_basic_session_data(treaty_id, current_user_name, authenticated_user, session, topic)
    |> assign_connection_state(is_connected, connection_status)
    |> configure_upload()
    |> assign_ui_state()
    |> assign(:showing_comments, false)
  end

  defp assign_basic_session_data(socket, treaty_id, current_user_name, authenticated_user, session, topic) do
    socket
    |> assign(:treaty_id, treaty_id)
    |> assign(:current_user, current_user_name)
    |> assign(:user_object, authenticated_user)
    |> assign(:token, session["user_token"])
    |> assign(:topic, topic)
  end

  defp configure_upload(socket) do
    allow_upload(socket, :image,
      accept: ChatConfig.get_config_value(:upload, :allowed_image_types),
      max_entries: ChatConfig.get_config_value(:upload, :max_entries),
      max_file_size: ChatConfig.get_config_value(:upload, :max_file_size),
      auto_upload: ChatConfig.get_config_value(:upload, :auto_upload)
    )
  end

  defp create_error_socket(socket, treaty_id, session) do
    socket
    |> assign(:treaty_id, treaty_id)
    |> assign(:current_user, "Usuario")
    |> assign(:user_object, nil)
    |> assign(:token, session["user_token"])
    |> assign(:topic, "treaty:#{treaty_id}")
    |> assign(:loading_error, true)
    |> assign(:connected, false)
    |> assign(:connection_status, "Erro de conexão")
    |> assign_empty_data()
    |> configure_upload()
    |> assign_ui_state()
  end

  defp assign_empty_data(socket) do
    socket
    |> assign(:treaty, %{treaty_code: socket.assigns.treaty_id, status: "Indisponível", title: "Não carregado"})
    |> assign(:messages, [])
    |> assign(:has_more_messages, false)
    |> assign(:presences, %{})
    |> assign(:users_online, [])
    |> assign(:message_count, 0)
    |> assign(:treaty_ratings, [])
    |> assign(:treaty_activities, [])
    |> assign(:treaty_stats, %{})
    |> assign(:treaty_comments, [])
    |> assign(:read_receipts, %{})
  end

  defp setup_connection_if_connected(socket, topic, current_user_name, authenticated_user, treaty_id) do
    if connected?(socket) do
      setup_pubsub_subscriptions(topic, authenticated_user)
      setup_presence_tracking(topic, socket, current_user_name, authenticated_user, treaty_id)
      schedule_connection_status_update()
    end
    socket
  end

  defp load_initial_data(socket, treaty_id, topic, _authenticated_user) do
    try do
      socket
      |> load_treaty_data(treaty_id)
      |> load_message_data(treaty_id)
      |> load_presence_data(topic)
      |> load_additional_data(treaty_id)
    rescue
      error ->
        require Logger
        Logger.warning("Failed to load initial data for treaty #{treaty_id}: #{inspect(error)}")
        assign_empty_data(socket)
    end
  end

  defp load_treaty_data(socket, treaty_id) do
    treaty_data = fetch_treaty_with_fallback(treaty_id)
    assign(socket, :treaty, treaty_data)
  end

  defp load_message_data(socket, treaty_id) do
    {message_history, has_more_messages} = safely_load_paginated_messages(treaty_id)
    read_receipts = safely_get_read_receipts(message_history, treaty_id)

    socket
    |> assign(:messages, message_history)
    |> assign(:has_more_messages, has_more_messages)
    |> assign(:message_count, length(message_history))
    |> assign(:read_receipts, read_receipts)
  end

  defp load_presence_data(socket, topic) do
    current_presences = safely_get_presences(topic)
    online_users = extract_users_from_presences(current_presences || %{})

    socket
    |> assign(:presences, current_presences || %{})
    |> assign(:users_online, online_users)
  end

  defp load_additional_data(socket, treaty_id) do
    treaty_ratings = safely_get_treaty_ratings(socket.assigns.treaty.id)
    treaty_activities = safely_get_treaty_activities(socket.assigns.treaty.id, ChatConfig.get_config_value(:activities, :default_limit))
    treaty_stats = safely_get_treaty_stats(socket.assigns.treaty.id)
    treaty_comments = safely_get_treaty_comments(socket.assigns.treaty.id)

    socket
    |> TagManager.load_treaty_tags(treaty_id)
    |> assign(:treaty_ratings, treaty_ratings)
    |> assign(:treaty_activities, treaty_activities)
    |> assign(:treaty_stats, treaty_stats)
    |> assign(:treaty_comments, treaty_comments)
  end

  defp setup_pubsub_subscriptions(topic, authenticated_user) do
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    if authenticated_user do
      Phoenix.PubSub.subscribe(App.PubSub, "user:#{authenticated_user.id}")
    end
  end

  defp setup_presence_tracking(topic, socket, user_name, authenticated_user, treaty_id) do
    user_data = %{
      user_id: AuthHelper.get_user_id_for_presence(authenticated_user),
      name: user_name,
      joined_at: DateTimeHelper.now() |> DateTime.to_iso8601(),
      user_agent: get_connect_info(socket, :user_agent) || "Desconhecido"
    }

    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
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

  defp schedule_connection_status_update do
    Process.send_after(self(), :update_connection_status, ChatConfig.get_config_value(:messages, :connection_check_interval))
  end

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

  defp safely_load_paginated_messages(treaty_id) when is_binary(treaty_id) do
    try do
      case App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.get_config_value(:messages, :default_message_limit)) do
        {:ok, messages, has_more} -> {messages, has_more}
      end
    rescue
      _ -> {[], false}
    end
  end

  defp safely_get_presences(topic) do
    try do
      Presence.list(topic)
    rescue
      _ -> %{}
    end
  end

  defp get_user_initial(user) when is_binary(user) and byte_size(user) > 0 do
    user |> String.first() |> String.upcase()
  end

  defp get_user_initial(_), do: "U"

  defp safely_get_treaty_ratings(nil), do: []
  defp safely_get_treaty_ratings(treaty_id) when is_integer(treaty_id) or is_binary(treaty_id) do
    try do
      App.Treaties.get_treaty_ratings(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_activities(nil, _limit), do: []
  defp safely_get_treaty_activities(treaty_id, limit) when (is_integer(treaty_id) or is_binary(treaty_id)) and is_integer(limit) do
    try do
      App.Treaties.get_treaty_activities(treaty_id, limit)
    rescue
      _ -> []
    end
  end

  defp safely_get_treaty_stats(nil), do: %{}
  defp safely_get_treaty_stats(treaty_id) when is_integer(treaty_id) or is_binary(treaty_id) do
    try do
      App.Treaties.get_treaty_stats(treaty_id)
    rescue
      _ -> %{}
    end
  end

  defp safely_get_treaty_comments(nil), do: []
  defp safely_get_treaty_comments(treaty_id) when is_integer(treaty_id) or is_binary(treaty_id) do
    try do
      App.TreatyComments.get_treaty_comments(treaty_id)
    rescue
      _ -> []
    end
  end

  defp safely_get_read_receipts(messages, treaty_id) do
    try do
      message_ids = Enum.map(messages, & &1.id)
      App.Chat.get_read_receipts_for_messages(message_ids, treaty_id)
    rescue
      _ -> %{}
    end
  end


  defp format_message_with_mentions(text) when is_binary(text) do
    text
    |> String.replace(~r/@([\w\.-]+)/, ~s(<span class="bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded-md text-xs font-medium">@\\1</span>))
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
    |> assign_message_state()
    |> assign_modal_states()
    |> assign_form_states()
    |> assign_animation_states()
    |> TagManager.initialize_tag_state()
    |> update_can_close_treaty()
  end

  defp assign_message_state(socket) do
    socket
    |> assign(:message, "")
    |> assign(:loading_messages, false)
    |> assign(:message_error, nil)
    |> assign(:typing_users, [])
    |> assign(:show_typing_indicator, false)
  end

  defp assign_modal_states(socket) do
    socket
    |> assign(:modal_image_url, nil)
    |> assign(:show_sidebar, false)
    |> assign(:show_close_modal, false)
    |> assign(:show_activities_modal, false)
  end

  defp assign_form_states(socket) do
    socket
    |> assign(:close_reason, "")
    |> assign(:resolution_notes, "")
    |> assign(:rating_value, "")
    |> assign(:rating_comment, "")
  end

  defp assign_animation_states(socket) do
    socket
    |> assign(:modal_animation_state, "closed")
    |> assign(:drag_drop_state, "idle")
    |> assign(:connection_transition_state, "stable")
    |> assign(:button_interaction_state, %{})
    |> assign(:skeleton_loading, false)
    |> assign(:message_animation_queue, [])
  end

  @doc """
  Processa o envio de mensagens com validação e verificações de segurança.

  Valida o conteúdo da mensagem, lida com uploads de imagens e transmite
  a mensagem para todos os usuários conectados na sala de chat do pedido.
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

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :message_error, nil)}
  end

  def handle_event("stopPropagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_older_messages", _params, socket) do
    if socket.assigns.loading_messages do
      {:noreply, socket}
    else
      {:noreply,
        socket
        |> assign(:loading_messages, true)
        |> assign(:skeleton_loading, true)
        |> load_older_messages_async()
      }
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    if connected?(socket) && String.length(message) > 0 do
      if socket.assigns[:typing_timer] do
        Process.cancel_timer(socket.assigns.typing_timer)
      end

      timer_ref = Process.send_after(self(), :trigger_typing_start, ChatConfig.get_config_value(:messages, :typing_indicator_delay))

      {:noreply, socket |> assign(:typing_timer, timer_ref) |> assign(:message, message)}
    else
      {:noreply, assign(socket, :message, message)}
    end
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
      |> assign(:modal_image_url, nil)
    }
  end

  def handle_event("toggle_comments", _params, socket) do
    {:noreply, assign(socket, :showing_comments, !socket.assigns.showing_comments)}
  end

  @impl true
  def handle_event("create_comment", %{"content" => _content, "comment_type" => _comment_type}, %{assigns: %{user_object: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Você precisa estar logado para criar comentários")}
  end

  @impl true
  def handle_event("create_comment", %{"content" => content, "comment_type" => comment_type}, %{assigns: %{user_object: user, treaty: %{id: treaty_id}}} = socket) do
    case App.TreatyComments.create_comment(%{
      treaty_id: treaty_id,
      user_id: user.id,
      content: content,
      comment_type: comment_type
    }) do
      {:ok, _comment} ->
        updated_comments = safely_get_treaty_comments(treaty_id)
        {:noreply,
          socket
          |> assign(:treaty_comments, updated_comments)
          |> put_flash(:info, "Comentário criado com sucesso")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Erro ao criar comentário: #{"Campo obrigatório ausente"}")}
    end
  end

  @impl true
  def handle_event("create_comment", _params, socket) do
    {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
  end

  @impl true
  def handle_event("edit_comment", %{"comment_id" => comment_id, "content" => content}, %{assigns: %{treaty: %{id: treaty_id}}} = socket) do
    case App.TreatyComments.update_comment(comment_id, %{content: content}) do
      {:ok, _comment} ->
        updated_comments = safely_get_treaty_comments(treaty_id)
        {:noreply,
          socket
          |> assign(:treaty_comments, updated_comments)
          |> put_flash(:info, "Comentário atualizado com sucesso")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Comentário não encontrado")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Erro ao atualizar comentário: #{"Campo obrigatório ausente"}")}
    end
  end

  @impl true
  def handle_event("edit_comment", _params, socket) do
    {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
  end

  @impl true
  def handle_event("delete_comment", %{"comment_id" => comment_id}, %{assigns: %{treaty: %{id: treaty_id}}} = socket) do
    case App.TreatyComments.delete_comment(comment_id) do
      {:ok, _comment} ->
        updated_comments = safely_get_treaty_comments(treaty_id)
        {:noreply,
          socket
          |> assign(:treaty_comments, updated_comments)
          |> put_flash(:info, "Comentário removido com sucesso")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Comentário não encontrado")}
    end
  end

  @impl true
  def handle_event("delete_comment", _params, socket) do
    {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
  end








  def handle_event("handle_keyup", %{"key" => key}, socket) do
    case key do
      "k" -> {:noreply, assign(socket, :show_search, true)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("exit_chat", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
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
    {:noreply, TagManager.show_tag_modal(socket)}
  end

  @impl true
  def handle_event("hide_tag_modal", _params, socket) do
    {:noreply, TagManager.hide_tag_modal(socket)}
  end

  @impl true
  def handle_event("search_tags", params, socket) do
    {:noreply, TagManager.search_tags(socket, params)}
  end

  @impl true
  def handle_event("add_tag_to_treaty", params, socket) do
    {:noreply, TagManager.add_tag_to_treaty(socket, params)}
  end

  @impl true
  def handle_event("remove_tag_from_treaty", params, socket) do
    {:noreply, TagManager.remove_tag_from_treaty(socket, params)}
  end

  @impl true
  def handle_event("show_close_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:show_close_modal, true)
      |> assign(:modal_animation_state, "opening")
      |> push_event("modal-opening", %{modal: "close"})
    }
  end

  @impl true
  def handle_event("hide_close_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:modal_animation_state, "closing")
      |> push_event("modal-closing", %{modal: "close"})
      |> then(fn socket ->
        Process.send_after(self(), :close_close_modal, 300)
        socket
      end)
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
  def handle_event("close_treaty", _params, %{assigns: %{user_object: nil}} = socket) do
    {:noreply,
      socket
      |> push_event("show-toast", %{
        type: "error",
        title: "Erro",
        message: "Você precisa estar logado para encerrar tratativas.",
        duration: 5000
      })
    }
  end

  @impl true
  def handle_event("close_treaty", _params, %{assigns: %{rating_value: ""}} = socket) do
    {:noreply,
      socket
      |> push_event("show-toast", %{
        type: "error",
        title: "Avaliação obrigatória",
        message: "Por favor, selecione uma avaliação antes de encerrar a tratativa.",
        duration: 5000
      })
    }
  end

  @impl true
  def handle_event("close_treaty", _params, %{assigns: %{user_object: user, treaty: treaty, close_reason: reason, resolution_notes: notes, rating_value: rating, rating_comment: rating_comment}} = socket) do
    if App.Accounts.can_close_treaty?(user, treaty) do
      close_attrs = %{
        close_reason: reason || "",
        resolution_notes: notes || ""
      }

      case App.Treaties.close_treaty(treaty, user.id, close_attrs) do
          {:ok, updated_treaty} ->
            case App.Treaties.add_rating(updated_treaty.id, user.id, rating, rating_comment) do
              {:ok, _rating} ->
                treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, ChatConfig.get_config_value(:activities, :default_limit))
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
                treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, ChatConfig.get_config_value(:activities, :default_limit))
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

  @impl true
  def handle_event("close_treaty", _params, socket) do
    {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
  end

  @impl true
  def handle_event("reopen_treaty", _params, %{assigns: %{user_object: nil}} = socket) do
    {:noreply,
      socket
      |> push_event("show-toast", %{
        type: "error",
        title: "Erro",
        message: "Você precisa estar logado para reabrir tratativas.",
        duration: 5000
      })
    }
  end

  @impl true
  def handle_event("reopen_treaty", _params, %{assigns: %{user_object: user, treaty: treaty}} = socket) do
    if App.Accounts.can_close_treaty?(user, treaty) do
      case App.Treaties.reopen_treaty(treaty, user.id) do
        {:ok, updated_treaty} ->
          treaty_activities = App.Treaties.get_treaty_activities(updated_treaty.id, ChatConfig.get_config_value(:activities, :default_limit))
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

  @impl true
  def handle_event("reopen_treaty", _params, socket) do
    {:noreply, put_flash(socket, :error, "Tratativa não encontrada")}
  end



  @impl true
  def handle_event("show_activities_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:show_activities_modal, true)
      |> assign(:modal_animation_state, "opening")
      |> push_event("modal-opening", %{modal: "activities"})
    }
  end

  @impl true
  def handle_event("hide_activities_modal", _params, socket) do
    {:noreply,
      socket
      |> assign(:modal_animation_state, "closing")
      |> push_event("modal-closing", %{modal: "activities"})
      |> then(fn socket ->
        Process.send_after(self(), :close_activities_modal, 300)
        socket
      end)
    }
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

  @impl true
  def handle_event("mark_messages_as_read", %{"message_ids" => message_keys}, socket) do
    case socket.assigns.user_object do
      nil ->
        {:noreply, socket}

      user ->
        treaty_id = socket.assigns.treaty_id
        message_ids = parse_message_ids(message_keys)

        Enum.each(message_ids, fn message_id ->
          safe_mark_message_as_read(message_id, user.id, treaty_id)
        end)

        updated_receipts = load_updated_read_receipts(message_ids, treaty_id, socket.assigns.read_receipts)

        broadcast_read_receipts(socket.assigns.topic, message_ids, user.id, treaty_id)

        {:noreply, assign(socket, :read_receipts, updated_receipts)}
    end
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

  defp validate_message_length(text) when is_binary(text) and byte_size(text) > 0 do
    max_length = ChatConfig.get_config_value(:security, :max_message_length)

    case byte_size(text) > max_length do
      true -> {:error, "Mensagem muito longa"}
      false -> {:ok, :valid}
    end
  end

  defp validate_message_length(text) when is_binary(text) and byte_size(text) == 0 do
    {:ok, :valid}
  end

  defp validate_message_length(_), do: {:ok, :valid}

  defp validate_connection(socket) do
    if connected?(socket) do
      {:ok, :valid}
    else
      {:error, "Conexão perdida. Tente recarregar a página."}
    end
  end

  defp validate_treaty_status(%{assigns: %{treaty: %{status: "closed"}}}) do
    {:error, "Esta tratativa está encerrada. Não é possível enviar mensagens."}
  end

  defp validate_treaty_status(_socket) do
    {:ok, :valid}
  end

  defp update_can_close_treaty(socket) do
    can_close = AuthHelper.can_close_treaty?(socket)
    assign(socket, :can_close_treaty, can_close)
  end

  defp process_message_send(socket, trimmed_text) do
    file_info = handle_image_upload(socket)
    {user_id, _user_name} = AuthHelper.get_user_info_for_message(socket)

    with {:ok, _message} <- App.Chat.send_message(socket.assigns.treaty_id, user_id, trimmed_text, file_info) do
      {:noreply,
        socket
        |> assign(:message, "")
        |> assign(:message_error, nil)
      }
    else
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
      [] ->
        nil
      [_entry | _] ->
        consume_uploaded_entries(socket, :image, &process_upload_entry/2)
        |> Enum.filter(&(&1 != nil))
    end
  end

  defp process_upload_entry(%{path: path}, entry) do
    temp_path = create_temp_file(path, entry.client_name)

    {:ok, %{
      temp_path: temp_path,
      original_filename: entry.client_name,
      file_size: entry.client_size,
      mime_type: entry.client_type,
      pending_upload: true
    }}
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
      :ok -> temp_path
      {:error, _reason} ->
        source_path
    end
  end

  @impl true
  def handle_info({:new_message, msg}, socket) do
    try do
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
      updated_socket = socket
      |> update(:messages, fn messages ->
        Enum.map(messages, fn msg ->
          if msg.id == message_id do
            try do
              attachments = App.Chat.get_message_attachments(message_id)
              %{msg | attachments: attachments}
            rescue
              _ -> msg
            end
          else
            msg
          end
        end)
      end)
      |> push_event("upload-complete", %{message_id: message_id, file_url: file_url})

      {:noreply, updated_socket}
    rescue
      _error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:wallpaper_applied, %{wallpaper_url: _url}}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:notification, :new_message, notification_data}, socket) do
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
        |> push_event("play-notification-sound", %{})
        |> push_event("update-badge-count", %{})
      }
    else
      {:noreply, socket}
    end
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
      |> assign(:skeleton_loading, false)
      |> push_event("messages-loaded", %{count: length(older_messages)})
    }
  end

  @impl true
  def handle_info({:treaty_tags_updated, treaty_tags}, socket) do
    {:noreply, TagManager.handle_tags_updated(socket, treaty_tags)}
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
  def handle_info(:trigger_typing_start, socket) do
    if connected?(socket) do
      Phoenix.PubSub.broadcast(App.PubSub, socket.assigns.topic, {:typing_start, socket.assigns.current_user})
      {:noreply, assign(socket, :typing_timer, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:read_receipts_updated, message_ids, _user_id, treaty_id}, socket) do
    if treaty_id == socket.assigns.treaty_id do
      updated_receipts = load_updated_read_receipts(message_ids, treaty_id, socket.assigns.read_receipts)

      {:noreply, assign(socket, :read_receipts, updated_receipts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:update_connection_status, socket) do
    is_connected = connected?(socket)
    connection_status = if(is_connected, do: "Conectado", else: "Desconectado")

    # Trigger connection transition animation
    transition_state = if is_connected != socket.assigns.connected do
      if is_connected, do: "connecting", else: "disconnecting"
    else
      "stable"
    end

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

    if is_connected do
      Process.send_after(self(), :update_connection_status, ChatConfig.get_config_value(:messages, :connection_check_interval))
    end

    {:noreply,
      socket
      |> assign(:connected, is_connected)
      |> assign(:connection_status, connection_status)
      |> assign(:connection_transition_state, transition_state)
      |> push_event("connection-status", %{connected: is_connected, status: connection_status, transition: transition_state})
      |> then(fn socket ->
        if transition_state != "stable" do
          Process.send_after(self(), :reset_connection_transition, 1000)
        end
        socket
      end)
    }
  end


  @impl true
  def handle_info(:close_tag_modal, socket) do
    {:noreply, TagManager.close_tag_modal(socket)}
  end

  @impl true
  def handle_info(:close_close_modal, socket) do
    {:noreply,
      socket
      |> assign(:show_close_modal, false)
      |> assign(:modal_animation_state, "closed")
      |> assign(:close_reason, "")
      |> assign(:resolution_notes, "")
      |> assign(:rating_value, "")
      |> assign(:rating_comment, "")
    }
  end

  @impl true
  def handle_info(:close_activities_modal, socket) do
    {:noreply,
      socket
      |> assign(:show_activities_modal, false)
      |> assign(:modal_animation_state, "closed")
    }
  end

  @impl true
  def handle_info(:reset_connection_transition, socket) do
    {:noreply, assign(socket, :connection_transition_state, "stable")}
  end

  @impl true
  def terminate(_reason, socket) do
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
         class="h-screen w-full bg-gray-50 font-sans antialiased flex flex-col lg:flex-row overflow-hidden m-0 p-0 relative"
         phx-hook="ChatCompositeHook"
         role="main">

      <!-- Área principal do chat -->
      <main class="flex-1 h-full flex flex-col bg-white min-w-0 lg:border-l border-gray-200 max-w-none m-0 p-0 shadow-sm" role="main" aria-label="Área de chat">
        <!-- Header do Chat -->
        <header class="flex flex-col sm:flex-row items-start sm:items-center justify-between px-3 sm:px-4 py-2 sm:py-3 border-b border-gray-200 bg-gradient-to-r from-white to-gray-50 flex-shrink-0 shadow-sm sticky top-0 z-10">
          <div class="flex items-center w-full">
            <div class="flex items-center space-x-2 flex-1 min-w-0">
              <div class="w-7 h-7 sm:w-8 sm:h-8 bg-gradient-to-br from-blue-600 to-blue-800 rounded-lg flex items-center justify-center shadow-sm">
                <svg class="w-4 h-4 sm:w-5 sm:h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                </svg>
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex items-center space-x-2">
                  <h1 class="text-sm sm:text-base font-bold text-gray-900 truncate">#<%= @treaty.treaty_code %></h1>
                  <span class={obter_classes_status(@treaty.status)}>
                    <%= @treaty.status %>
                  </span>
                </div>
                <div class="flex flex-wrap items-center mt-1 space-x-2 sm:space-x-3">
                  <div class="flex items-center">
                    <div class={get_connection_indicator_class(@connected, @connection_transition_state)} aria-hidden="true"></div>
                    <span class={get_connection_text_class(@connected, @connection_transition_state)}><%= @connection_status %></span>
                  </div>
                  <div class="flex items-center text-xs text-gray-500">
                    <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
                    </svg>
                    <span class="font-medium"><%= length(@users_online) %></span>
                  </div>
                </div>
              </div>
            </div>
          </div>

           <div class="flex items-center space-x-1 mt-1 sm:mt-0">
            <!-- Botão para abrir sidebar no mobile -->
            <button phx-click="toggle_sidebar" class="lg:hidden p-1.5 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transform hover:scale-110 active:scale-95"
                    aria-label="Abrir sidebar com tags e usuários online"
                    title="Tags e usuários online">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
              </svg>
            </button>

            <!-- Botão de comentários internos -->
            <button phx-click="toggle_comments" class={[
              "p-1.5 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-offset-1 transform hover:scale-110 active:scale-95",
              if(@showing_comments, do: "text-blue-600 bg-blue-50", else: "text-gray-500 hover:text-blue-600 hover:bg-blue-50")
            ]}
                    aria-label={if(@showing_comments, do: "Ocultar comentários", else: "Mostrar comentários internos")}
                    title={if(@showing_comments, do: "Ocultar comentários", else: "Comentários internos")}>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 8h10m0 0V6a2 2 0 00-2-2H9a2 2 0 00-2 2v2m10 0a2 2 0 012 2v6a2 2 0 01-2 2H9a2 2 0 01-2-2v-6a2 2 0 012-2h8z"></path>
              </svg>
            </button>

            <!-- Botão de atividades/tracking -->
            <button phx-click="show_activities_modal" class="p-1.5 text-gray-500 hover:text-indigo-600 hover:bg-indigo-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-indigo-500 focus:ring-offset-1 transform hover:scale-110 active:scale-95"
                    aria-label="Ver atividades da tratativa"
                    title="Histórico de atividades">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </button>

            <!-- Botão de encerrar/reabrir tratativa -->
            <%= if @can_close_treaty do %>
              <%= if @treaty.status == "closed" do %>
                <button phx-click="reopen_treaty" class="p-1.5 text-gray-500 hover:text-green-600 hover:bg-green-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-green-500 focus:ring-offset-1"
                        aria-label="Reabrir tratativa"
                        title="Reabrir tratativa">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                </button>
              <% else %>
                <button phx-click="show_close_modal" class="p-1.5 text-gray-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-red-500 focus:ring-offset-1"
                        aria-label="Encerrar tratativa"
                        title="Encerrar tratativa">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              <% end %>
            <% end %>

            <button
              phx-click="exit_chat"
              class="p-1.5 text-gray-500 hover:text-red-600 hover:bg-red-50 transition-all duration-200 rounded-lg hover:shadow-sm focus:ring-2 focus:ring-red-500 focus:ring-offset-1"
              title="Sair do chat e voltar para busca de tratativas"
              aria-label="Sair do chat"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path>
              </svg>
            </button>
          </div>
        </header>

        <!-- Componente de Comentários Internos -->
        <%= if @showing_comments do %>
          <div class="mx-2 sm:mx-3 mt-1 p-3 bg-gradient-to-r from-blue-50 to-indigo-50 border border-blue-200 rounded-lg shadow-sm">
            <!-- Header dos Comentários -->
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center">
                <svg class="w-4 h-4 text-blue-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 8h10m0 0V6a2 2 0 00-2-2H9a2 2 0 00-2 2v2m10 0a2 2 0 012 2v6a2 2 0 01-2 2H9a2 2 0 01-2-2v-6a2 2 0 012-2h8z"></path>
                </svg>
                <h3 class="text-sm font-semibold text-gray-900">Comentários Internos</h3>
                <span class="ml-2 px-2 py-0.5 text-xs bg-blue-100 text-blue-800 rounded-full">
                  <%= length(@treaty_comments) %>
                </span>
              </div>
              <button phx-click="toggle_comments" class="text-blue-500 hover:text-blue-700 p-1 hover:bg-blue-100 rounded-lg transition-colors">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>

            <!-- Formulário para novo comentário -->
            <form phx-submit="create_comment" class="mb-3">
              <div class="flex space-x-2 mb-2">
                <select name="comment_type" class="px-2 py-1 text-xs border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                  <option value="internal_note">Interno</option>
                  <option value="public_note">Público</option>
                </select>
                <button type="submit" class="px-3 py-1 text-xs bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors">
                  Adicionar
                </button>
              </div>
              <textarea
                name="content"
                placeholder="Adicione uma nota interna sobre esta tratativa..."
                rows="2"
                class="w-full px-3 py-2 text-sm border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-none"
                required
              ></textarea>
            </form>

            <!-- Lista de comentários -->
            <div class={"space-y-2 #{ChatConfig.get_config_value(:comments, :max_display_height)} overflow-y-auto"}>
              <%= for comment <- @treaty_comments do %>
                <div class="p-2 bg-white border border-blue-200 rounded-lg">
                  <div class="flex items-start justify-between mb-1">
                    <div class="flex items-center">
                      <span class={[
                        "px-1.5 py-0.5 text-xs rounded-full",
                        if(comment.comment_type == "internal_note", do: "bg-blue-100 text-blue-800", else: "bg-green-100 text-green-800")
                      ]}>
                        <%= if comment.comment_type == "internal_note", do: "Interno", else: "Público" %>
                      </span>
                      <span class="ml-2 text-xs text-gray-500">
                        <%= format_time(comment.inserted_at) %>
                      </span>
                    </div>
                    <div class="flex space-x-1">
                      <button phx-click="edit_comment" phx-value-comment_id={comment.id} class="text-gray-400 hover:text-blue-600 p-1">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                        </svg>
                      </button>
                      <button phx-click="delete_comment" phx-value-comment_id={comment.id} class="text-gray-400 hover:text-red-600 p-1">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                        </svg>
                      </button>
                    </div>
                  </div>
                  <p class="text-sm text-gray-700"><%= comment.content %></p>
                </div>
              <% end %>

              <%= if Enum.empty?(@treaty_comments) do %>
                <div class="text-center text-sm text-gray-500 py-4">
                  Nenhum comentário ainda.
                </div>
              <% end %>
            </div>
          </div>
        <% end %>



        <!-- Error Message -->
        <%= if @message_error do %>
          <div class="mx-2 md:mx-3 mt-1 p-1.5 bg-red-50 border border-red-200 rounded-lg flex items-center justify-between">
            <div class="flex items-center">
              <svg class="w-3 h-3 text-red-500 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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


        <!-- Messages Container -->
        <div class="flex-1 flex overflow-hidden">
          <div id="messages"
               class="flex-1 overflow-y-auto px-2 sm:px-3 md:px-4 py-2 sm:py-3 md:py-4 bg-gradient-to-b from-gray-50/50 to-white scroll-smooth min-h-0"
               role="log"
               aria-live="polite"
               aria-label="Mensagens do chat">

          <!-- Load More Button -->
          <%= if @has_more_messages do %>
            <div class="flex justify-center pb-2">
              <button
                phx-click="load_older_messages"
                disabled={@loading_messages}
                class={"px-2.5 py-1 text-xs text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed flex items-center space-x-1 shadow-sm hover:shadow-md transform hover:scale-105 active:scale-95 " <>
                       if(@loading_messages, do: "btn-loading", else: "")}>
                <%= if @loading_messages do %>
                  <svg class="w-3 h-3 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  <span>Carregando...</span>
                <% else %>
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"></path>
                  </svg>
                  <span>Anteriores</span>
                <% end %>
              </button>
            </div>
          <% end %>

          <!-- Skeleton Loading -->
          <%= if @skeleton_loading do %>
            <div class="space-y-3 animate-pulse">
              <%= for _i <- 1..3 do %>
                <div class="flex justify-start">
                  <div class="max-w-[85%] px-3 py-2 rounded-xl bg-gray-200">
                    <div class="h-3 bg-gray-300 rounded w-16 mb-1"></div>
                    <div class="h-4 bg-gray-300 rounded w-32"></div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>

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
                  <%= render_message(message, index, @messages, @user_object, @read_receipts, @current_user) %>
              <% end %>
          <% end %>

        </div>

        <!-- Sidebar com usuários online e tags -->
          <div class={"#{ChatConfig.get_config_value(:ui, :sidebar_width)} bg-white border-l border-gray-200 overflow-y-auto transition-transform #{ChatConfig.get_config_value(:ui, :transition_duration)} ease-in-out " <>
                if(@show_sidebar, do: "translate-x-0", else: "translate-x-full") <>
                " lg:translate-x-0 lg:block " <>
                if(@show_sidebar, do: "fixed inset-y-0 right-0 #{ChatConfig.get_config_value(:ui, :sidebar_z_index)}", else: "hidden lg:block")}
                role="complementary"
                aria-label="Sidebar com tags e usuários online">
            <!-- Header da sidebar com botão de fechar no mobile -->
            <div class="lg:hidden flex items-center justify-between p-3 border-b border-gray-200 bg-gray-50">
              <h2 class="text-base font-semibold text-gray-900">Menu</h2>
              <button phx-click="close_sidebar"
                      class="p-1.5 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-all duration-200 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                      aria-label="Fechar menu">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                      </svg>
              </button>
                </div>


            <!-- Seção de Tags -->
            <div class="p-3 border-b border-gray-200">
              <div class="flex items-center justify-between mb-2">
                <h3 class="text-xs font-semibold text-gray-900">Tags</h3>
                <button phx-click="show_tag_modal"
                        class="p-1.5 text-gray-500 hover:text-blue-600 hover:bg-blue-50 transition-all duration-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                        aria-label="Gerenciar tags"
                        title="Gerenciar tags">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                  </svg>
                </button>
              </div>
              <%= if not Enum.empty?(@treaty_tags) do %>
                <div class="space-y-1.5">
                  <%= for tag <- @treaty_tags do %>
                    <div class="flex items-center justify-between p-1.5 bg-gray-50 rounded-lg">
                      <div class="flex items-center space-x-1.5">
                        <div class="w-2.5 h-2.5 rounded-full" style={"background-color: #{tag.color}"}></div>
                        <span class="text-xs font-medium text-gray-700"><%= tag.name %></span>
                      </div>
                      <button phx-click="remove_tag_from_treaty"
                              phx-value-tag_id={tag.id}
                              class="p-1 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-all duration-200 focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
                              title="Remover tag"
                              aria-label={"Remover tag #{tag.name}"}>
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                        </svg>
                      </button>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-xs text-gray-500 text-center py-1.5">Nenhuma tag adicionada</p>
              <% end %>
            </div>

            <!-- Seção de Usuários Online -->
            <%= if not Enum.empty?(@users_online) do %>
              <div class="p-3">
                <h3 class="text-xs font-semibold text-gray-900 mb-2">Usuários Online</h3>
                <div class="space-y-1.5">
                  <%= for user <- @users_online do %>
                    <div class="flex items-center space-x-2 p-1.5 rounded-lg hover:bg-gray-50 transition-colors">
                      <div class="w-6 h-6 bg-gradient-to-br from-blue-500 to-blue-700 rounded-full flex items-center justify-center shadow-sm">
                        <span class="text-white text-xs font-bold"><%= get_user_initial(user) %></span>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-xs font-medium text-gray-900 truncate"><%= user %></p>
                        <p class="text-xs text-green-600">Online</p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Rodapé da Sidebar com usuário atual -->
            <div class="mt-auto p-3 border-t border-gray-200 bg-gray-50">
              <div class="flex items-center space-x-2">
                <div class="w-6 h-6 bg-gradient-to-br from-green-500 to-green-700 rounded-full flex items-center justify-center shadow-sm">
                  <span class="text-white text-xs font-bold"><%= get_user_initial(@current_user) %></span>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-medium text-gray-900 truncate"><%= @current_user %></p>
                  <p class="text-xs text-gray-500">Você</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Typing Indicator -->
        <%= if @show_typing_indicator && @typing_users && length(@typing_users) > 0 do %>
          <div class="px-2 md:px-3 py-0.5 bg-gray-50/50 border-t border-gray-100">
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
        <footer class="p-2 sm:p-3 border-t border-gray-200 bg-gradient-to-r from-white to-gray-50/50 backdrop-blur-sm flex-shrink-0 shadow-lg sticky bottom-0 z-10">
          <!-- Status de Conexão -->
          <div class="mb-1 flex items-center justify-between text-xs">
            <div class="flex items-center space-x-1" role="status" aria-live="polite">
              <div class={get_connection_indicator_class(@connected, @connection_transition_state)} aria-hidden="true"></div>
              <span class={get_connection_text_class(@connected, @connection_transition_state)}>
                <%= if @connected do %>
                  Conectado
                <% else %>
                  <%= if @treaty.status == "closed" do %>
                    Tratativa encerrada
                  <% else %>
                    Desconectado
                  <% end %>
                <% end %>
              </span>
              <%= if @connected and length(@users_online) > 1 do %>
                <span class="text-green-500 text-xs">
                  (<%= length(@users_online) - 1 %> outro<%= if length(@users_online) > 2, do: "s", else: "" %>)
                </span>
              <% end %>
            </div>
            <%= if @message_error do %>
              <div class="text-red-500 font-medium" role="alert" aria-live="assertive">{@message_error}</div>
            <% end %>
          </div>

          <form phx-submit="send_message" phx-drop-target={if @treaty.status != "closed" and @uploads[:image], do: @uploads.image.ref, else: nil} class="flex items-end space-x-1.5 sm:space-x-3 transition-all duration-200" role="form" aria-label="Enviar mensagem">
            <div class="flex-1 relative">
              <label for="message-input" class="sr-only">Digite sua mensagem</label>
              <!-- Drag and drop overlay -->
              <div class={"fixed inset-0 bg-gradient-to-br from-blue-500/30 via-blue-400/20 to-blue-600/30 backdrop-blur-md flex items-center justify-center pointer-events-none transition-all duration-300 z-50 " <>
                       if(@drag_drop_state == "dragging", do: "opacity-100", else: "opacity-0")}
                   id="drag-overlay">
                <div class={"bg-white/95 backdrop-blur-lg rounded-3xl p-8 shadow-2xl border border-blue-200/50 transition-all duration-300 max-w-sm mx-4 " <>
                       if(@drag_drop_state == "dragging", do: "scale-100", else: "scale-95")}
                   id="drag-content">
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
                      <div class="upload-preview-container rounded-lg border border-gray-200 shadow-md hover:shadow-lg transition-shadow duration-200 overflow-hidden bg-gray-100">
                        <.live_img_preview entry={entry} class="upload-preview-image" />
                      </div>

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
                class="w-full px-3 py-2 sm:px-4 sm:py-3 pr-10 sm:pr-12 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all duration-200 bg-white shadow-sm hover:border-blue-300 hover:shadow-md text-sm sm:text-base focus:outline-none disabled:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-60"
                autocomplete="off"
                maxlength={ChatConfig.get_config_value(:security, :max_message_length)}
                disabled={not @connected or @treaty.status == "closed"}
                phx-change="update_message"
                aria-describedby="message-help"
                aria-invalid={if @message_error, do: "true", else: "false"}
                role="textbox"
                aria-label="Campo de entrada de mensagem"
              />
              <div id="message-help" class="sr-only">
                Digite sua mensagem. Máximo de <%= ChatConfig.get_config_value(:security, :max_message_length) %> caracteres.
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
              <label for="image-upload" class={"absolute right-2 sm:right-3 top-1/2 transform -translate-y-1/2 p-1.5 sm:p-2 text-gray-400 hover:text-blue-600 transition-all duration-200 rounded-lg hover:bg-blue-50 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 " <> if(@treaty.status == "closed", do: "cursor-not-allowed opacity-50", else: "cursor-pointer")} aria-label="Anexar arquivo" title="Anexar arquivo">
                <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"></path>
                </svg>
                <.live_file_input upload={@uploads.image} id="image-upload" class="hidden" phx-change="validate" phx-upload="upload" disabled={@treaty.status == "closed"} />
              </label>
            </div>

            <button
              type="submit"
              disabled={String.trim(@message) == "" && @uploads.image.entries == [] or @treaty.status == "closed"}
              class="px-4 py-2 sm:px-6 sm:py-3 bg-gradient-to-r from-blue-600 to-blue-700 text-white rounded-xl hover:from-blue-700 hover:to-blue-800 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 font-semibold flex items-center space-x-1 sm:space-x-2 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed phx-submit-loading:opacity-75 text-sm sm:text-base min-w-[50px] sm:min-w-[60px] transform hover:scale-105 active:scale-95 disabled:transform-none"
              aria-label="Enviar mensagem"
              aria-describedby="send-button-help"
              title={if String.trim(@message) == "" && @uploads.image.entries == [], do: "Gravar áudio", else: "Enviar mensagem"}>
              <%= if String.trim(@message) == "" && @uploads.image.entries == [] do %>
                <!-- Ícone do microfone estilo WhatsApp -->
                <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.49 6-3.31 6-6.72h-1.7z"/>
                </svg>
                <span class="hidden sm:inline">Voz</span>
              <% else %>
                <span class="hidden sm:inline">Enviar</span>
                <span class="sm:hidden">→</span>


                <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"></path>
                </svg>
              <% end %>
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
      <div class="fixed inset-0 bg-black/50 #{ChatConfig.get_config_value(:ui, :overlay_z_index)} md:hidden" phx-click="toggle_sidebar" aria-hidden="true"></div>
    <% end %>

    <%= if @modal_image_url do %>
      <div class="fixed inset-0 #{ChatConfig.get_config_value(:ui, :modal_z_index)} flex items-center justify-center bg-black/70" phx-click="close_image_modal">
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
      <div class={"fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-backdrop-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-backdrop-out", else: "")}
           phx-click="hide_tag_modal">
        <div class={"bg-white rounded-2xl shadow-2xl max-w-md w-full max-h-[80vh] overflow-hidden transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-out", else: "")}
           phx-click="stopPropagation">
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
                       phx-debounce={ChatConfig.get_config_value(:search, :debounce_delay)}
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



    <!-- Modal de Encerrar Tratativa -->
    <%= if @show_close_modal do %>
      <div class={"fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-backdrop-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-backdrop-out", else: "")}
           phx-click="hide_close_modal">
        <div id="close-modal" class={"bg-white rounded-2xl shadow-2xl max-w-md w-full transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-out", else: "")}
           phx-click="stopPropagation" phx-hook="RatingHook">
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
      <div class={"fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-backdrop-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-backdrop-out", else: "")}
           phx-click="hide_activities_modal">
        <div class={"bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[80vh] overflow-hidden transition-all duration-300 " <>
                   if(@modal_animation_state == "opening", do: "animate-modal-in", else: "") <>
                   if(@modal_animation_state == "closing", do: "animate-modal-out", else: "")}
           phx-click="stopPropagation">
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
      with {:ok, older_messages, has_more} <- App.Chat.list_messages_for_treaty(treaty_id, ChatConfig.get_config_value(:pagination, :default_limit), current_count) do
        send(self(), {:older_messages_loaded, older_messages, has_more})
      else
        {:error, _reason} ->
          send(self(), {:older_messages_loaded, [], false})
      end
    end)

    socket
  end


  defp classes_base, do: "px-2.5 py-1 text-xs font-semibold rounded-full border shadow-sm transition-all duration-200"

  defp obter_classes_status("active"), do: classes_base() <> " bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100"
  defp obter_classes_status("inactive"), do: classes_base() <> " bg-amber-50 text-amber-700 border-amber-200 hover:bg-amber-100"
  defp obter_classes_status("cancelled"), do: classes_base() <> " bg-red-50 text-red-700 border-red-200 hover:bg-red-100"
  defp obter_classes_status("completed"), do: classes_base() <> " bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100"
  defp obter_classes_status("closed"), do: classes_base() <> " bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"
  defp obter_classes_status(_), do: classes_base() <> " bg-gray-50 text-gray-700 border-gray-200 hover:bg-gray-100"

  defp get_connection_indicator_class(true, "connecting") do
    "w-1.5 h-1.5 rounded-full mr-1 bg-yellow-500 animate-pulse shadow-sm transition-colors duration-500"
  end
  defp get_connection_indicator_class(true, "stable") do
    "w-1.5 h-1.5 rounded-full mr-1 bg-emerald-500 animate-pulse shadow-sm transition-colors duration-500"
  end
  defp get_connection_indicator_class(false, "disconnecting") do
    "w-1.5 h-1.5 rounded-full mr-1 bg-yellow-500 animate-pulse shadow-sm transition-colors duration-500"
  end
  defp get_connection_indicator_class(false, "stable") do
    "w-1.5 h-1.5 rounded-full mr-1 bg-red-500 shadow-sm transition-colors duration-500"
  end
  defp get_connection_indicator_class(_, _) do
    "w-1.5 h-1.5 rounded-full mr-1 bg-gray-500 shadow-sm transition-colors duration-500"
  end

  defp get_connection_text_class(true, "connecting") do
    "text-yellow-600 font-medium transition-colors duration-500"
  end
  defp get_connection_text_class(true, "stable") do
    "text-emerald-600 font-medium transition-colors duration-500"
  end
  defp get_connection_text_class(false, "disconnecting") do
    "text-yellow-600 font-medium transition-colors duration-500"
  end
  defp get_connection_text_class(false, "stable") do
    "text-red-600 font-medium transition-colors duration-500"
  end
  defp get_connection_text_class(_, _) do
    "text-gray-600 font-medium transition-colors duration-500"
  end


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

  defp render_message(message, index, message_list, user_object, read_receipts, current_user) do
    is_current_user = case user_object do
      nil -> false
      user -> user.id == message.sender_id
    end

    previous_message = if index > 0, do: Enum.at(message_list, index - 1), else: nil
    show_date_separator = should_show_date_separator(message, previous_message)

    message_receipts = get_read_receipts_for_message(message.id, read_receipts)
    read_by_text = format_read_by_list(message.id, read_receipts, current_user)
    message_status = get_message_status(message, message_receipts)

    assigns = %{
      message: message,
      index: index,
      message_list: message_list,
      user_object: user_object,
      is_current_user: is_current_user,
      show_date_separator: show_date_separator,
      read_receipts: message_receipts,
      read_by_text: read_by_text,
      message_status: message_status,
      current_user: current_user
    }

    ~H"""
    <%= if @show_date_separator do %>
      <!-- Separador de Data -->
      <div class="flex items-center justify-center my-2">
        <div class="bg-gray-100 text-gray-600 text-xs font-medium px-2 py-0.5 rounded-full shadow-sm border border-gray-200">
          <%= format_date_separator(@message.timestamp || @message.inserted_at) %>
        </div>
      </div>
    <% end %>
    <div class={"flex mb-2 animate-slide-in transition-all duration-300 hover:scale-[1.02] " <> if(@is_current_user, do: "justify-end", else: "justify-start")}
         role="article"
         aria-label={"Mensagem de " <> @message.sender_name}>
      <div class={
        "relative max-w-[90%] sm:max-w-[85%] md:max-w-md lg:max-w-lg xl:max-w-xl px-2.5 sm:px-3 py-2 rounded-xl shadow-md transition-all duration-200 hover:shadow-lg " <>
        if(@is_current_user,
          do: "bg-gradient-to-br from-blue-500 to-blue-600 text-white rounded-br-lg",
          else: "bg-white text-gray-900 rounded-bl-lg border border-gray-200 shadow-sm hover:border-gray-300")
      }>
        <%= if not @is_current_user do %>
          <div class="text-xs font-semibold text-gray-700 mb-0.5"><%= @message.sender_name %></div>
        <% end %>
        <div class="text-sm break-words leading-relaxed"><%= format_message_with_mentions(@message.text) %></div>
        <%= if @message.attachments && length(@message.attachments) > 0 do %>
          <div class="mt-1.5 space-y-1.5">
            <%= for attachment <- @message.attachments do %>
              <%= if attachment.file_type == "image" do %>
                <div class="chat-image-container rounded-lg cursor-pointer hover:scale-105 transition-all duration-300 shadow-md hover:shadow-lg bg-gray-100"
                     phx-click="show_image"
                     phx-value-url={attachment.file_url}>
                  <img src={attachment.file_url}
                       class="chat-image-thumbnail"
                       alt={attachment.original_filename}
                       loading="lazy" />
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
        <div class="flex items-center justify-end mt-0.5 space-x-1">
          <span class={"text-xs " <> if(@is_current_user, do: "text-white/70", else: "text-gray-400")}><%= format_time(@message.inserted_at) %></span>
          <%= if @is_current_user do %>
            <!-- Status dos checks estilo WhatsApp -->
            <%= cond do %>
              <% @message_status == :read -> %>
                <!-- Dois checks azuis = Mensagem lida ✓✓ -->
                <div class="flex items-center">
                  <svg class="w-3 h-3 text-blue-400" fill="currentColor" viewBox="0 0 6 8">
                    <path d="M1.5 4l.8.8 2.2-2.2" stroke="white" stroke-width="0.5" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                  <svg class="w-3 h-3 text-blue-400 -ml-1" fill="currentColor" viewBox="0 0 6 8">
                    <path d="M1.5 4l.8.8 2.2-2.2" stroke="white" stroke-width="0.5" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                </div>
                <!-- Opcionalmente mostrar quando fez leitura -->
                <%= if @read_by_text != "" do %>
                  <span class="text-xs text-white/60 ml-1"><%= @read_by_text %></span>
                <% end %>
              <% true -> %>
                <!-- Um check cinza = Mensagem enviada ✓ -->
                <svg class="w-3 h-3 text-white/50" fill="none" stroke="currentColor" viewBox="0 0 8 6">
                  <path d="M2 3l1.5 1.5 3-3" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp parse_message_ids(message_keys) when is_list(message_keys) do
    message_keys
    |> Enum.map(&parse_single_message_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_single_message_id(key) do
    case Integer.parse(to_string(key)) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp safe_mark_message_as_read(message_id, user_id, treaty_id) do
    try do
      App.Chat.mark_message_as_read(message_id, user_id, treaty_id)
    rescue
      _ -> :ok
    end
  end

  defp load_updated_read_receipts(message_ids, treaty_id, current_receipts) do
    try do
      new_receipts = App.Chat.get_read_receipts_for_messages(message_ids, treaty_id)
      Map.merge(current_receipts, new_receipts)
    rescue
      _ -> current_receipts
    end
  end


  defp get_read_receipts_for_message(message_id, read_receipts) do
    Map.get(read_receipts, message_id, [])
  end

  defp format_read_by_list(_message_id, _read_receipts, _current_user_name, []), do: ""

  defp format_read_by_list(_message_id, _read_receipts, _current_user_name, [receipt]) do
    user_name = receipt.user_name || receipt.username || "Usuário"
    "#{user_name} leu"
  end

  defp format_read_by_list(_message_id, _read_receipts, current_user_name, receipts) do
    user_names = receipts
    |> Enum.map(fn receipt -> receipt.user_name || receipt.username end)
    |> Enum.reject(fn name -> name == current_user_name end)

    case user_names do
      [] -> "Você leu"
      names ->
        names_str = join_names_smartly(names)
        "#{names_str} leram"
    end
  end

  defp format_read_by_list(message_id, read_receipts, current_user_name) do
    receipts = get_read_receipts_for_message(message_id, read_receipts)
    format_read_by_list(message_id, read_receipts, current_user_name, receipts)
  end

  defp get_message_status(_message, read_receipts) when length(read_receipts) > 0, do: :read
  defp get_message_status(_message, _read_receipts), do: :sent

  defp join_names_smartly([name]), do: name
  defp join_names_smartly([first, second]), do: "#{first} e #{second}"
  defp join_names_smartly([first, second | rest]) do
    last = List.last(rest)
    middle_count = length(rest) - 1
    "#{first} e mais #{middle_count} outros#{if last != second, do: " e #{last}", else: ""}"
  end

  defp broadcast_read_receipts(topic, message_ids, user_id, treaty_id) do
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:read_receipts_updated, message_ids, user_id, treaty_id})
  end

end
