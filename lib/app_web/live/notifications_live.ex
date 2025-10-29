defmodule AppWeb.NotificationsLive do
  @moduledoc """
  LiveView para sistema de notificações e celebrações.

  Responsável por gerenciar notificações de metas atingidas,
  celebrações e efeitos visuais/sonoros.

  Recebe eventos do PubSub e exibe notificações temporárias (8 segundos)
  com efeitos visuais e sonoros.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardNotificationPanel
  import AppWeb.DashboardUtils

  @notification_duration_ms 8_000
  @max_notifications 10

  @type notification :: map()
  @type celebration_data :: map()

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
    end

    socket = assign(socket, %{
      notifications: [],
      show_celebration: false
    })

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:daily_goal_achieved, data}, socket) do
    with {:ok, notification} <- build_legacy_notification(data),
         {:ok, event_data} <- build_legacy_event_data(data, notification) do
      add_notification_to_socket(socket, notification, "goal-achieved-multiple", event_data)
    else
      _error ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:goal_achieved_real, data}, socket) do
    with {:ok, notification} <- build_real_notification(data),
         {:ok, event_data} <- build_real_event_data(data, notification) do
      add_notification_to_socket(socket, notification, "goal-achieved-real", event_data)
    else
      _error ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:hide_celebration, socket) do
    {:noreply, assign(socket, show_celebration: false)}
  end

  @impl Phoenix.LiveView
  def handle_info({:hide_specific_notification, id}, socket) do
    updated_notifications = Enum.reject(socket.assigns.notifications, &(&1.celebration_id == id))
    has_notifications = updated_notifications != []

    {:noreply, assign(socket,
      notifications: updated_notifications,
      show_celebration: has_notifications
    )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <!-- Painel de Notificações -->
    <.notification_panel notifications={@notifications} />
    """
  end

  defp build_legacy_notification(data) when is_map(data) do
    celebration_id = Map.get(data, :celebration_id) || System.unique_integer([:positive])

    notification = %{
      id: celebration_id,
      celebration_id: celebration_id,
      store_name: safe_get(data, :store_name, "Loja Desconhecida"),
      achieved: safe_get(data, :achieved, 0.0),
      target: safe_get(data, :target, 0.0),
      percentage: safe_get(data, :percentage, 0.0),
      timestamp: safe_get(data, :timestamp, DateTime.utc_now())
    }

    {:ok, notification}
  end

  defp build_legacy_notification(_), do: {:error, :invalid_data}

  defp build_legacy_event_data(_data, notification) do
    formatted_achieved = format_money(notification.achieved)
    unix_timestamp = DateTime.to_unix(notification.timestamp, :millisecond)

    event_data = %{
      store_name: notification.store_name,
      achieved: formatted_achieved,
      celebration_id: notification.celebration_id,
      timestamp: unix_timestamp
    }

    {:ok, event_data}
  end

  defp build_real_notification(data) when is_map(data) do
    celebration_id = safe_get(data, :celebration_id, System.unique_integer([:positive]))
    celebration_data = safe_get(data, :data, %{})

    notification = %{
      id: celebration_id,
      celebration_id: celebration_id,
      store_name: safe_get(celebration_data, :store_name, "Loja Desconhecida"),
      achieved: safe_get(celebration_data, :achieved, 0.0),
      target: safe_get(celebration_data, :target, 0.0),
      percentage: safe_get(data, :percentage, 0.0),
      timestamp: safe_get(data, :timestamp, DateTime.utc_now()),
      type: safe_get(data, :type, :daily_goal),
      level: safe_get(data, :level, :standard),
      message: safe_get(celebration_data, :message, "Meta Atingida!"),
      supervisor_id: Map.get(celebration_data, :supervisor_id)
    }

    {:ok, notification}
  end

  defp build_real_notification(_), do: {:error, :invalid_data}

  defp build_real_event_data(data, notification) do
    formatted_achieved = format_money(notification.achieved)
    unix_timestamp = DateTime.to_unix(notification.timestamp, :millisecond)
    celebration_data = safe_get(data, :data, %{})
    sound = Map.get(celebration_data, :sound, "goal_achieved.mp3")

    event_data = %{
      type: notification.type,
      level: notification.level,
      message: notification.message,
      store_name: notification.store_name,
      achieved: formatted_achieved,
      celebration_id: notification.celebration_id,
      timestamp: unix_timestamp,
      sound: sound
    }

    {:ok, event_data}
  end

  defp add_notification_to_socket(socket, notification, event_name, event_data) do
    current_notifications = socket.assigns.notifications
    updated_notifications =
      if length(current_notifications) >= @max_notifications do
        Enum.take([notification | current_notifications], @max_notifications)
      else
        [notification | current_notifications]
      end

    socket
    |> assign(%{
      notifications: updated_notifications,
      show_celebration: true
    })
    |> push_event(event_name, event_data)
    |> schedule_notification_removal(notification.celebration_id)
  end

  defp schedule_notification_removal(socket, celebration_id) do
    Process.send_after(self(), {:hide_specific_notification, celebration_id}, @notification_duration_ms)
    {:noreply, socket}
  end

  defp safe_get(map, key, default) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
  end

  defp safe_get(_, _, default), do: default
end
