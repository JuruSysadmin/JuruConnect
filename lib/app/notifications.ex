defmodule App.Notifications do
  @moduledoc """
  Handles chat system notifications including message alerts and user mentions.
  """

  alias App.Accounts
  alias App.Notifications.Notification
  alias App.Repo
  import Ecto.Query

  @doc """
  Sends notification when a new message is received.

  Returns `{:ok, :notification_sent}` on success, or `{:ok, :no_notification_needed}`
  if the message is from the same user (self-message).
  """
  def notify_new_message(message, current_user_id) do
    with {:ok, _} <- prevent_self_notification(message, current_user_id),
         {:ok, user} <- fetch_user_by_id(current_user_id),
         {:ok, is_user_online} <- check_presence_in_treaty(message.treaty_id, current_user_id) do

      deliver_notification(message, user, is_user_online)
      {:ok, :notification_sent}
    else
      {:error, :self_message} ->
        {:ok, :no_notification_needed}
      {:error, :user_not_found} ->
        {:ok, :user_not_found}
      {:error, reason} ->
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
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp check_presence_in_treaty(treaty_id, user_id) do
    topic = "treaty:#{treaty_id}"
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
    # User is online - send real-time notification
    broadcast_liveview_notification(user.id, message)
    send_desktop_notification(user, message)
  end

  defp deliver_notification(message, user, false) do
    # User is offline - save notification and send desktop notification
    save_offline_notification(user.id, message)
    send_desktop_notification(user, message)
  end

  defp broadcast_liveview_notification(user_id, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:notification, :new_message, %{
        message: message,
        treaty_id: message.treaty_id,
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
      # Save mention notification to database
      save_mention_notification(user_id, message)
      broadcast_mention_notification(user_id, message)
      send_desktop_notification(user, message, :mention)
      {:ok, :mention_sent}
    else
      {:error, :user_not_found} ->
        {:error, :user_not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_mention_notification(user_id, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:notification, :mention, %{
        message: message,
        treaty_id: message.treaty_id,
        sender_name: message.sender_name,
        text: message.text,
        timestamp: message.inserted_at,
        mentioned_by: message.sender_name
      }}
    )
  end

  @doc """
  Retrieves unread notifications for a user.
  """
  def get_unread_notifications(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and n.is_read == false)
    |> order_by([n], desc: n.inserted_at)
    |> limit(50)
    |> Repo.all()
  end

  @doc """
  Retrieves all notifications for a user (read and unread).
  """
  def get_user_notifications(user_id, limit \\ 100) do
    Notification
    |> where([n], n.user_id == ^user_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Marks notifications as read for a user.
  """
  def mark_notifications_as_read(user_id, notification_ids) when is_list(notification_ids) do
    Notification
    |> where([n], n.user_id == ^user_id and n.id in ^notification_ids)
    |> Repo.update_all(set: [is_read: true, read_at: DateTime.utc_now()])
    |> case do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end

  def mark_notifications_as_read(user_id, notification_id) when is_binary(notification_id) do
    mark_notifications_as_read(user_id, [notification_id])
  end

  @doc """
  Marks all notifications as read for a user.
  """
  def mark_all_notifications_as_read(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and n.is_read == false)
    |> Repo.update_all(set: [is_read: true, read_at: DateTime.utc_now()])
    |> case do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end

  @doc """
  Gets the count of unread notifications for a user.
  """
  def get_unread_count(user_id) do
    Notification
    |> where([n], n.user_id == ^user_id and n.is_read == false)
    |> Repo.aggregate(:count)
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
    ~r/@([\w\.-]+)/
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
    "#{message.sender_name}: #{String.slice(message.text, 0, 100)}"
  end

  defp broadcast_desktop_notification(user_id, title, body, message) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:desktop_notification, %{
        title: title,
        body: body,
        icon: "/images/notification-icon.svg",
        sound: "/sounds/16451.mp3",
        tag: "chat-notification",
        data: %{
          treaty_id: message.treaty_id,
          message_id: message.id
        }
      }}
    )
  end

  defp save_offline_notification(user_id, message) do
    treaty_id = get_treaty_id_from_code(message.treaty_id)
    if is_nil(treaty_id) do
      {:ok, :treaty_not_found}
    else
      notification_attrs = %{
        user_id: user_id,
        treaty_id: treaty_id,
        message_id: message.id,
        sender_id: message.sender_id,
        sender_name: message.sender_name,
        notification_type: "new_message",
        title: "Nova mensagem",
        body: build_notification_body(message, :new_message),
        metadata: %{
          treaty_code: message.treaty_id,
          message_preview: String.slice(message.text, 0, 100)
        }
      }

      case Notification.create_changeset(notification_attrs) |> Repo.insert() do
        {:ok, notification} ->
          {:ok, notification}
        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end


  defp get_treaty_id_from_code(treaty_code) do
    case App.Treaties.get_treaty(treaty_code) do
      {:ok, treaty} -> treaty.id
      {:error, _} -> nil
    end
  end

  defp save_mention_notification(user_id, message) do
    # Get the actual treaty ID (binary_id) from treaty_code
    treaty_id = get_treaty_id_from_code(message.treaty_id)

    # Skip notification if treaty doesn't exist
    if is_nil(treaty_id) do
      {:ok, :treaty_not_found}
    else
      notification_attrs = %{
        user_id: user_id,
        treaty_id: treaty_id,
        message_id: message.id,
        sender_id: message.sender_id,
        sender_name: message.sender_name,
        notification_type: "mention",
        title: "Você foi mencionado!",
        body: build_notification_body(message, :mention),
        metadata: %{
          treaty_code: message.treaty_id,
          message_preview: String.slice(message.text, 0, 100),
          mentioned_by: message.sender_name
        }
      }

      case Notification.create_changeset(notification_attrs) |> Repo.insert() do
        {:ok, notification} ->
          {:ok, notification}
        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end
end
