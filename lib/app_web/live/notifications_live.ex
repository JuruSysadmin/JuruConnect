defmodule AppWeb.NotificationsLive do
  @moduledoc """
  LiveView para sistema de notificações e celebrações.

  Responsável por gerenciar notificações de metas atingidas,
  celebrações e efeitos visuais/sonoros.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardNotificationPanel
  import AppWeb.DashboardUtils

  # Constantes
  @notification_duration_ms 8_000
  @max_notifications 10

  @impl true
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

  @impl true
  def handle_info({:daily_goal_achieved, %{celebration_id: id} = data}, socket) do
    celebration_id = id || System.unique_integer([:positive])

    notification = %{
      id: celebration_id,
      store_name: data.store_name,
      achieved: data.achieved,
      target: data.target,
      percentage: data.percentage,
      timestamp: data.timestamp,
      celebration_id: celebration_id
    }

    formatted_achieved = format_money(data.achieved)
    unix_timestamp = DateTime.to_unix(data.timestamp, :millisecond)

    socket
    |> assign(%{
      notifications: [notification | socket.assigns.notifications] |> Enum.take(@max_notifications),
      show_celebration: true
    })
    |> push_event("goal-achieved-multiple", %{
      store_name: data.store_name,
      achieved: formatted_achieved,
      celebration_id: celebration_id,
      timestamp: unix_timestamp
    })
    |> then(fn socket ->
      Process.send_after(self(), {:hide_specific_notification, celebration_id}, @notification_duration_ms)
      {:noreply, socket}
    end)
  end

  @impl true
  def handle_info({:goal_achieved_real, data}, socket) do
    celebration_id = data.celebration_id

    notification = %{
      id: celebration_id,
      store_name: data.data.store_name,
      achieved: data.data.achieved,
      target: data.data.target,
      percentage: data.percentage,
      timestamp: data.timestamp,
      celebration_id: celebration_id,
      type: data.type,
      level: data.level,
      message: data.data.message,
      supervisor_id: Map.get(data.data, :supervisor_id)
    }

    formatted_achieved = format_money(notification.achieved)
    unix_timestamp = DateTime.to_unix(data.timestamp, :millisecond)
    sound = Map.get(data.data, :sound, "goal_achieved.mp3")

    socket
    |> assign(%{
      notifications: [notification | socket.assigns.notifications] |> Enum.take(@max_notifications),
      show_celebration: true
    })
    |> push_event("goal-achieved-real", %{
      type: data.type,
      level: data.level,
      message: notification.message,
      store_name: notification.store_name,
      achieved: formatted_achieved,
      celebration_id: celebration_id,
      timestamp: unix_timestamp,
      sound: sound
    })
    |> then(fn socket ->
      Process.send_after(self(), {:hide_specific_notification, celebration_id}, @notification_duration_ms)
      {:noreply, socket}
    end)
  end

  @impl true
  def handle_info(:hide_celebration, socket) do
    {:noreply, assign(socket, show_celebration: false)}
  end

  @impl true
  def handle_info({:hide_specific_notification, id}, socket) do
    updated = Enum.reject(socket.assigns.notifications, &(&1.celebration_id == id))
    show = updated != []

    {:noreply, assign(socket, notifications: updated, show_celebration: show)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Painel de Notificações -->
    <.notification_panel notifications={@notifications} />
    """
  end
end
