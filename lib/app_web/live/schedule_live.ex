defmodule AppWeb.ScheduleLive do
  @moduledoc """
  LiveView para agendamento de entregas.

  Responsável por exibir o card de agendamentos com dados em tempo real
  via PubSub.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardSchedule

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:schedule")
    end

    socket = assign(socket, %{
      schedule_data: []
    })

    # Busca dados iniciais
    socket = fetch_schedule_data(socket)

    {:ok, socket}
  end

  @impl true
  def handle_info({:schedule_updated, schedule_data}, socket) do
    schedule_list = if is_list(schedule_data), do: schedule_data, else: [schedule_data]
    {:noreply, assign(socket, schedule_data: schedule_list)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-4 min-w-0">
      <.schedule_card schedule_data={@schedule_data} />
    </div>
    """
  end

  # Funções privadas

  defp fetch_schedule_data(socket) do
    case App.ApiClient.fetch_schedule_data() do
      {:ok, data} ->
        schedule_list = if is_list(data), do: data, else: [data]
        assign(socket, schedule_data: schedule_list)
      {:error, _reason} ->
        assign(socket, schedule_data: [])
    end
  end
end
