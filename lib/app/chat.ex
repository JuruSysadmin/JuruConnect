defmodule App.Chat do
  @moduledoc """
  Chat context for managing messages and real-time communication.

  Provides functions for creating, retrieving, and managing chat messages
  with support for real-time updates, notifications, and order-based conversations.
  Handles message persistence, user presence tracking, and notification delivery.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Chat.Message
  require Logger

  def list_recent_messages(chat_id, message_limit \\ 100) do
    from(message in Message,
      where: message.chat_id == ^chat_id,
      order_by: [asc: message.inserted_at],
      limit: ^message_limit,
      select: %{
        id: message.id,
        text: message.text,
        sender: message.sender,
        tipo: message.tipo,
        timestamp: message.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Verifies if a user has access to a specific chat.

  Currently returns true for all users. Should be implemented with proper
  authorization logic based on business rules and user permissions.
  """
  def user_has_access?(_user_id, _chat_id), do: true

  @doc """
  Lists messages for a given chat, with pagination.
  """
  def list_messages(chat_id, pagination_opts \\ []) do
    offset = Keyword.get(pagination_opts, :offset, 0)
    message_limit = Keyword.get(pagination_opts, :limit, 50)

    query =
      from(message in Message,
        where: message.chat_id == ^chat_id,
        order_by: [desc: message.inserted_at],
        offset: ^offset,
        limit: ^message_limit
      )

    messages = Repo.all(query) |> Enum.reverse()
    has_more_messages = length(messages) == message_limit
    {:ok, messages, has_more_messages}
  end

  @doc """
  Creates and persists a new message.
  """
  def create_message(params) do
    %Message{}
    |> Message.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Retrieves messages from the chat session cache.

  Provides fast access to recently active messages without database queries,
  useful for real-time chat interfaces and session management.
  """
  def get_messages(_chat_id) do
    # ChatSession module not implemented yet - using empty list as fallback
    []
  end

  @doc """
  Lists messages for a specific order with pagination support.

  Retrieves messages associated with an order in chronological order,
  supporting pagination for efficient loading of conversation history.
  """
  def list_messages_for_order(order_id, message_limit \\ 50, offset \\ 0) do
    query =
      from(message in Message,
        where: message.order_id == ^order_id,
        order_by: [asc: message.inserted_at],
        offset: ^offset,
        limit: ^message_limit
      )

    messages = Repo.all(query)
    has_more_messages = length(messages) == message_limit
    {:ok, messages, has_more_messages}
  end

  @doc """
  Sends a message to a specific order with image support and notifications.

  Creates a new message, broadcasts it to connected clients via PubSub,
  and processes notifications for online users and mentioned users.
  """
  def send_message(order_id, sender_id, message_text, image_url \\ nil) do
    sender_name = resolve_sender_name(sender_id)
    message_params = build_message_params(order_id, sender_id, sender_name, message_text, image_url)

    case create_message(message_params) do
      {:ok, created_message} ->
        broadcast_message_to_order(created_message, order_id)
        process_message_notifications(created_message, order_id)

        # Marcar mensagem como entregue automaticamente
        Task.start(fn ->
          Process.sleep(100) # Pequeno delay para garantir que a mensagem foi processada
          mark_message_delivered(created_message.id)
        end)

        {:ok, created_message}
      {:error, changeset} ->
        Logger.error("Failed to create message: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp process_message_notifications(message, order_id) do
    online_user_ids = extract_online_user_ids(order_id)
    notify_online_users(message, online_user_ids)
    handle_message_mentions(message)
  end

  defp resolve_sender_name(nil), do: "Usuário Anônimo"
  defp resolve_sender_name(sender_id) when is_binary(sender_id) do
    case App.Accounts.get_user!(sender_id) do
      %{name: name} when not is_nil(name) -> name
      %{username: username} when not is_nil(username) -> username
      _ -> "Usuário"
    end
  end
  defp resolve_sender_name(_), do: "Usuário"

  defp build_message_params(order_id, sender_id, sender_name, message_text, image_url) do
    %{
      text: message_text,
      sender_id: sender_id,
      sender_name: sender_name,
      order_id: order_id,
      tipo: "mensagem",
      image_url: image_url
    }
  end

  defp broadcast_message_to_order(message, order_id) do
    topic = "order:#{order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
  end

  defp extract_online_user_ids(order_id) do
    topic = "order:#{order_id}"
    presences = AppWeb.Presence.list(topic)

    presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{user_id: user_id} -> user_id end)
    end)
    |> Enum.filter(&(&1 != "anonymous" && &1 != nil))
    |> Enum.uniq()
  end

  defp notify_online_users(message, online_user_ids) do
    Enum.each(online_user_ids, fn user_id ->
      App.Notifications.notify_new_message(message, user_id)
    end)
  end

  defp handle_message_mentions(message) do
    mentioned_users = App.Notifications.extract_mentions(message.text)
    if length(mentioned_users) > 0 do
      App.Notifications.notify_mention(message, mentioned_users)
    end
  end

  @doc """
  Marca uma mensagem como entregue.
  """
  def mark_message_delivered(message_id) do
    case Repo.get(Message, message_id) do
      nil -> {:error, :message_not_found}
      message ->
        changeset = Message.delivery_changeset(message, %{
          delivery_status: "delivered",
          delivered_at: DateTime.utc_now()
        })

        case Repo.update(changeset) do
          {:ok, updated_message} ->
            broadcast_message_status_update(updated_message)
            {:ok, updated_message}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Marca uma mensagem como lida por um usuário específico.
  """
  def mark_message_read(message_id, user_id) do
    case Repo.get(Message, message_id) do
      nil -> {:error, :message_not_found}
      message ->
        # Verificar se o usuário já leu a mensagem
        viewed_by = parse_viewed_by(message.viewed_by || "[]")

        if user_id in viewed_by do
          {:ok, message} # Já foi lida por este usuário
        else
          # Adicionar usuário à lista de visualizações
          updated_viewed_by = [user_id | viewed_by] |> Enum.uniq()

          changeset = Message.read_changeset(message, %{
            read_status: "read",
            read_at: DateTime.utc_now(),
            read_by: user_id,
            viewed_by: Jason.encode!(updated_viewed_by)
          })

          case Repo.update(changeset) do
            {:ok, updated_message} ->
              broadcast_message_status_update(updated_message)
              {:ok, updated_message}
            {:error, changeset} -> {:error, changeset}
          end
        end
    end
  end

  @doc """
  Marca uma mensagem como falha na entrega.
  """
  def mark_message_failed(message_id) do
    case Repo.get(Message, message_id) do
      nil -> {:error, :message_not_found}
      message ->
        changeset = Message.delivery_changeset(message, %{
          delivery_status: "failed"
        })

        case Repo.update(changeset) do
          {:ok, updated_message} ->
            broadcast_message_status_update(updated_message)
            {:ok, updated_message}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Obtém o status de leitura de todas as mensagens de um pedido.
  """
  def get_message_read_status(order_id) do
    from(message in Message,
      where: message.order_id == ^order_id,
      select: %{
        id: message.id,
        read_status: message.read_status,
        read_at: message.read_at,
        read_by: message.read_by,
        viewed_by: message.viewed_by,
        delivery_status: message.delivery_status,
        delivered_at: message.delivered_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Marca todas as mensagens não lidas de um pedido como lidas por um usuário.
  """
  def mark_all_messages_read_for_user(order_id, user_id) do
    # Buscar mensagens não lidas do pedido
    unread_messages = from(message in Message,
      where: message.order_id == ^order_id and message.read_status == "unread",
      where: message.sender_id != ^user_id  # Não marcar próprias mensagens como lidas
    )
    |> Repo.all()

    # Marcar cada mensagem como lida
    results = Enum.map(unread_messages, fn message ->
      mark_message_read(message.id, user_id)
    end)

    # Verificar se todas as operações foram bem-sucedidas
    failed_operations = Enum.filter(results, fn
      {:ok, _} -> false
      {:error, _} -> true
    end)

    if Enum.empty?(failed_operations) do
      {:ok, length(unread_messages)}
    else
      {:error, "Falha ao marcar #{length(failed_operations)} mensagens como lidas"}
    end
  end

  @doc """
  Obtém estatísticas de leitura para um pedido.
  """
  def get_reading_stats(order_id) do
    total_messages = from(message in Message,
      where: message.order_id == ^order_id,
      select: count(message.id)
    ) |> Repo.one()

    read_messages = from(message in Message,
      where: message.order_id == ^order_id and message.read_status == "read",
      select: count(message.id)
    ) |> Repo.one()

    %{
      total: total_messages,
      read: read_messages,
      unread: total_messages - read_messages
    }
  end

  defp parse_viewed_by(nil), do: []
  defp parse_viewed_by(""), do: []
  defp parse_viewed_by(viewed_by_json) do
    case Jason.decode(viewed_by_json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp broadcast_message_status_update(message) do
    topic = "order:#{message.order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:message_status_update, message})
  end
end
