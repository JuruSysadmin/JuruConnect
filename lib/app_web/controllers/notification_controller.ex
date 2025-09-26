defmodule AppWeb.NotificationController do
  use AppWeb, :controller

  alias App.Notifications
  alias App.Notifications.Notification

  action_fallback AppWeb.FallbackController

  def index(conn, _params) do
    user_id = get_current_user_id(conn)
    notifications = Notifications.get_user_notifications(user_id)
    render(conn, :index, notifications: notifications)
  end

  def unread_count(conn, _params) do
    user_id = get_current_user_id(conn)
    count = Notifications.get_unread_count(user_id)

    conn
    |> put_status(:ok)
    |> json(%{count: count})
  end

  def mark_as_read(conn, %{"id" => id}) do
    user_id = get_current_user_id(conn)

    case Notifications.mark_notifications_as_read(user_id, id) do
      {:ok, _count} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true})
      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to mark notification as read"})
    end
  end

  def mark_all_as_read(conn, _params) do
    user_id = get_current_user_id(conn)

    case Notifications.mark_all_notifications_as_read(user_id) do
      {:ok, count} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true, count: count})
      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to mark notifications as read"})
    end
  end

  defp get_current_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end
end
