defmodule AppWeb.StoresPerformanceLive do
  @moduledoc """
  LiveView para tabela de performance das lojas.

  Responsável por exibir a tabela com dados de vendas por loja/supervisor,
  incluindo animações e modal de detalhes do supervisor.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardStoresTable
  import AppWeb.SupervisorModal

  alias App.Dashboard.SupervisorMonitor

  @impl true
  def mount(_params, _session, socket) do
    # PubSub é usado para receber atualizações em tempo real do dashboard
    # sem precisar fazer polling constante
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

  @impl true
  def handle_info({:dashboard_updated, data}, socket) do
    # Conversão para atoms é necessária para ter acesso consistente aos dados
    # independentemente da origem (API retorna strings como keys)
    data = convert_keys_to_atoms(data)

    socket = socket
    |> assign_stores_data(data)
    |> assign(%{loading: false})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:supervisor_updated, supervisor_data}, socket) do
    {:noreply, assign(socket, supervisor_data: supervisor_data)}
  end

  @impl true
  def handle_event("show_supervisor_drawer", %{"supervisor-id" => id}, socket) do
    # Topic único permite múltiplos clientes visualizarem o mesmo supervisor
    # sem interferência entre sessões
    topic = "supervisor:#{id}"
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    # SupervisorMonitor garante que só busca dados no banco quando necessário,
    # evitando queries repetidas desnecessárias
    SupervisorMonitor.subscribe_supervisor(id)

    socket = assign(socket, %{
      show_drawer: true,
      supervisor_loading: true,
      supervisor_topic: topic,
      supervisor_id: id
    })

    # Busca assíncrona mantém a LiveView responsiva enquanto busca dados externos
    case fetch_supervisor_data(id) do
      data when is_list(data) ->
        {:noreply, assign(socket, supervisor_data: data, supervisor_loading: false)}
      _ ->
        {:noreply, assign(socket, supervisor_data: [], supervisor_loading: false)}
    end
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    # Cleanup é essencial para evitar memory leaks e subscriptions órfãs
    # quando o usuário navega para outra página sem fechar o drawer
    if topic = socket.assigns[:supervisor_topic] do
      Phoenix.PubSub.unsubscribe(App.PubSub, topic)
    end

    # SupervisorMonitor precisa saber quando clientes param de visualizar
    # para otimizar as queries de atualização
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

  @impl true
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
    # Armazenar o estado anterior permite detectar mudanças nos valores
    # para animações visuais quando vendas aumentam
    previous_lojas_map = Map.get(socket.assigns, :previous_lojas_data, %{})

    processed_companies = process_companies_with_animation(companies, previous_lojas_map)

    assign(socket, %{
      lojas_data: processed_companies,
      # Guarda apenas supervisor_id e venda_dia por ser suficiente para animação
      # e manter o estado leve
      previous_lojas_data: Map.new(companies, fn loja -> {loja.supervisor_id, loja.venda_dia} end)
    })
  end

  defp get_companies_data(%{companies: companies}) when is_list(companies), do: companies
  defp get_companies_data(_), do: []

  defp process_companies_with_animation(companies, previous_lojas_map) do
    # Flag de animação só aciona quando há incremento real de vendas
    # (não no primeiro load quando previous_value é 0)
    # Isso evita flashes de animação desnecessários ao carregar a página
    Enum.map(companies, fn loja ->
      previous_value = Map.get(previous_lojas_map, loja.supervisor_id, 0.0)
      increment = loja.venda_dia - previous_value
      animate_venda_dia = increment > 0 and previous_value > 0

      loja
      |> Map.put(:animate_venda_dia, animate_venda_dia)
      |> Map.put(:increment_value, increment)
    end)
  end

  defp fetch_supervisor_data(id) do
    case App.ApiClient.fetch_supervisor_data(id) do
      {:ok, sale_supervisors} -> sale_supervisors
      {:error, _reason} -> []
    end
  end

  defp convert_keys_to_atoms(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> convert_key_to_atom(k, v) end)
    |> Enum.into(%{})
  end

  defp convert_keys_to_atoms(_), do: %{}

  # String.to_existing_atom evita criar novos atoms dinamicamente,
  # prevenindo memory leaks por atoms não coletados pelo GC
  # Se o atom não existir, mantém a key original como fallback seguro
  defp convert_key_to_atom(k, v) when is_binary(k) do
    {String.to_existing_atom(k), v}
  rescue
    ArgumentError -> {k, v}
  end

  defp convert_key_to_atom(k, v), do: {k, v}
end
