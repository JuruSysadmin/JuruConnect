defmodule App.Notifications do
  @moduledoc """
  Handles chat system notifications including message alerts and user mentions.
  """

  alias App.Accounts
  alias App.Chat
  require Logger

  @doc """
  Sends notification when a new message is received.

  Returns `{:ok, :notification_sent}` on success, or `{:ok, :no_notification_needed}`
  if the message is from the same user (self-message).
  """
  def notify_new_message(message, current_user_id) do
    with {:ok, _} <- prevent_self_notification(message, current_user_id),
         {:ok, user} <- fetch_user_by_id(current_user_id),
         {:ok, is_user_online} <- check_presence_in_order(message.order_id, current_user_id) do

      deliver_notification(message, user, is_user_online)
      {:ok, :notification_sent}
    else
      {:error, :self_message} ->
        {:ok, :no_notification_needed}
      {:error, :user_not_found} ->
        Logger.warning("Usuário não encontrado para notificação: #{current_user_id}")
        {:ok, :user_not_found}
      {:error, reason} ->
        Logger.error("Erro ao enviar notificação: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp prevent_self_notification(message, current_user_id) when message.sender_id == current_user_id do
    {:error, :self_message}
  end
  defp prevent_self_notification(_message, _current_user_id) do
    {:ok, :valid}
  end

  defp fetch_user_by_id(user_id) do
    case Accounts.get_user!(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp check_presence_in_order(order_id, user_id) do
    topic = "order:#{order_id}"
    presences = AppWeb.Presence.list(topic)

    is_user_online = presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{user_id: user_id} -> user_id end)
    end)
    |> Enum.member?(user_id)

    {:ok, is_user_online}
  end

  defp deliver_notification(message, user, true) do
    broadcast_liveview_notification(user.id, message)
  end

  defp deliver_notification(message, user, false) do
    save_offline_notification(user.id, message)
    send_desktop_notification(user, message)
  end

  defp broadcast_liveview_notification(user_id, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:notification, :new_message, %{
        message: message,
        order_id: message.order_id,
        sender_name: message.sender_name,
        text: message.text,
        timestamp: message.inserted_at
      }}
    )
  end

  @doc """
  Sends notifications when users are mentioned in a message.

  Returns `{:ok, count}` where count is the number of successful notifications sent.
  """
  def notify_mention(message, mentioned_users) do
    mentioned_users
    |> Enum.map(&send_mention_notification(message, &1))
    |> Enum.filter(&match?({:ok, _}, &1))
    |> length()
    |> then(fn count -> {:ok, count} end)
  end

  defp send_mention_notification(message, user_id) do
    with {:ok, user} <- fetch_user_by_id(user_id) do
      broadcast_mention_notification(user_id, message)
      send_desktop_notification(user, message, :mention)
      {:ok, :mention_sent}
    else
      {:error, :user_not_found} ->
        Logger.warning("Usuário mencionado não encontrado: #{user_id}")
        {:error, :user_not_found}
      {:error, reason} ->
        Logger.error("Erro ao enviar notificação de menção: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_mention_notification(user_id, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:notification, :mention, %{
        message: message,
        order_id: message.order_id,
        sender_name: message.sender_name,
        text: message.text,
        timestamp: message.inserted_at,
        mentioned_by: message.sender_name
      }}
    )
  end

  @doc """
  Retrieves unread notifications for a user.

  Currently returns an empty list as the notification storage is not yet implemented.
  """
  def get_unread_notifications(user_id) do
    []
  end

  @doc """
  Marks notifications as read for a user.

  Currently a no-op as the notification storage is not yet implemented.
  """
  def mark_notifications_as_read(user_id, notification_ids) do
    :ok
  end

  @doc """
  Extracts user mentions (@username) from message text and returns their user IDs.

  Returns a list of user IDs for valid usernames found in the text.
  """
  def extract_mentions(text) when is_binary(text) and byte_size(text) > 0 do
    text
    |> find_mentioned_usernames()
    |> Enum.map(&get_user_id_by_username/1)
    |> Enum.filter(&(&1 != nil))
  end
  def extract_mentions(_), do: []

  defp find_mentioned_usernames(text) do
    ~r/@(\w+)/
    |> Regex.scan(text)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end

  defp get_user_id_by_username(username) do
    case Accounts.get_user_by_username(username) do
      nil -> nil
      user -> user.id
    end
  end

  @doc """
  Sends desktop notification via JavaScript to the user's browser.

  Only sends if desktop notifications are enabled in the chat configuration.
  """
  def send_desktop_notification(user, message, type \\ :new_message) do
    notification_config = App.ChatConfig.notification_config()

    if notification_config[:enable_desktop_notifications] do
      title = build_notification_title(type)
      body = build_notification_body(message, type)

      broadcast_desktop_notification(user.id, title, body, message)
    end
  end

  defp build_notification_title(:mention), do: "Você foi mencionado!"
  defp build_notification_title(_), do: "Nova mensagem"

  defp build_notification_body(message, :mention) do
    "#{message.sender_name} mencionou você: #{String.slice(message.text, 0, 50)}"
  end
  defp build_notification_body(message, _) do
    "#{message.sender_name}: #{String.slice(message.text, 0, 50)}"
  end

  defp broadcast_desktop_notification(user_id, title, body, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:desktop_notification, %{
        title: title,
        body: body,
        icon: "/images/notification-icon.svg",
        tag: "chat-notification",
        data: %{
          order_id: message.order_id,
          message_id: message.id
        }
      }}
    )
  end

  @doc """
  Saves notification for offline user.

  Currently logs the action as the notification storage is not yet implemented.
  """
  defp save_offline_notification(user_id, message) do
    Logger.info("Salvando notificação offline para usuário #{user_id}")
    :ok
  end
end
