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
end
