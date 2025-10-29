defmodule AppWeb.StoresPerformanceLive do
  @moduledoc """
  LiveView para tabela de performance das lojas.

  Responsável por exibir a tabela com dados de vendas por loja/supervisor,
  incluindo animações e modal de detalhes do supervisor.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardStoresTable
  import AppWeb.SupervisorModal
  import AppWeb.DashboardState

  alias App.Dashboard.SupervisorMonitor

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    end

    socket = assign(socket, %{
      lojas_data: [],
      loading: true,
      show_drawer: false,
      supervisor_data: [],
      supervisor_loading: false,
      supervisor_topic: nil,
      supervisor_id: nil
    })

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:dashboard_updated, data}, socket) do
    data = convert_keys_to_atoms(data)

    socket = socket
    |> assign_stores_data(data)
    |> assign(%{loading: false})

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:supervisor_updated, supervisor_data}, socket) do
    {:noreply, assign(socket,
      supervisor_data: supervisor_data,
      supervisor_loading: false
    )}
  end

  @impl Phoenix.LiveView
  def handle_event("show_supervisor_drawer", %{"supervisor-id" => id}, socket) do
    topic = "supervisor:#{id}"
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    # SupervisorMonitor já busca os dados automaticamente após subscribe
    # e faz broadcast via PubSub, então não precisamos buscar aqui
    SupervisorMonitor.subscribe_supervisor(id)

    {:noreply, assign(socket, %{
      show_drawer: true,
      supervisor_loading: true,
      supervisor_topic: topic,
      supervisor_id: id
    })}
  end

  @impl Phoenix.LiveView
  def handle_event("close_drawer", _params, socket) do
    if topic = socket.assigns[:supervisor_topic] do
      Phoenix.PubSub.unsubscribe(App.PubSub, topic)
    end

    if supervisor_id = socket.assigns[:supervisor_id] do
      SupervisorMonitor.unsubscribe_supervisor(supervisor_id)
    end

    {:noreply, assign(socket,
      show_drawer: false,
      supervisor_data: [],
      supervisor_topic: nil,
      supervisor_id: nil,
      supervisor_loading: false
    )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-3 sm:p-4 hover:shadow-xl transition-shadow duration-300 min-w-0">
      <!-- Header -->
      <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-3 space-y-2 sm:space-y-0">
        <div class="min-w-0 flex-1">
          <h2 class="text-sm sm:text-base font-bold text-gray-900 mb-0.5 flex items-center gap-2 truncate">
            Performance das Lojas
          </h2>
          <p class="text-xs text-gray-500 truncate">
            {length(@lojas_data)} lojas ativas • Atualização em tempo real
          </p>
        </div>
        <div class="flex items-center space-x-2 px-2.5 py-1 bg-green-50 rounded-full border border-green-200 flex-shrink-0" role="status" aria-label="Sistema em tempo real">
          <div class="w-2 h-2 rounded-full bg-green-500 animate-pulse" aria-hidden="true"></div>
          <span class="text-xs text-green-700 font-bold">AO VIVO</span>
        </div>
      </div>

      <!-- Tabela Responsiva -->
      <.stores_table lojas_data={@lojas_data} loading={@loading} />

      <!-- Modal do Supervisor -->
      <.supervisor_modal
        show={@show_drawer}
        supervisor_data={@supervisor_data}
        loading={@supervisor_loading}
        on_close="close_drawer"
      />
    </div>
    """
  end

  # Funções privadas

  defp assign_stores_data(socket, data) do
    companies = get_companies_data(data)
    previous_lojas_map = Map.get(socket.assigns, :previous_lojas_data, %{})

    processed_companies = process_companies_with_animation(data, previous_lojas_map)

    assign(socket, %{
      lojas_data: processed_companies,
      previous_lojas_data: create_previous_lojas_map(companies)
    })
  end

end
