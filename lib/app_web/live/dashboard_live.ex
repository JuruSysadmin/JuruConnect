defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view

  alias App.DashboardDataServer
  import AppWeb.DashboardComponents
  import AppWeb.DashboardUtils

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1000, self(), :fetch_data)

    # Busca dados iniciais do GenServer
    socket = fetch_and_assign_data(socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:fetch_data, socket) do
    socket = fetch_and_assign_data(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Mantém a funcionalidade de tick para animações visuais
    socket = update(socket, :tick, &(&1 + 1))
    {:noreply, socket}
  end

  defp fetch_and_assign_data(socket) do
    state = DashboardDataServer.get_data()
    data = state.data || %{}
    api_status = state.api_status
    api_error = state.api_error
    last_update = state.last_update

    if api_status == :ok do
      assign_success_data(socket, data)
      |> assign(api_status: api_status, last_update: last_update)
    else
      assign_error_data(socket, api_error)
      |> assign(last_update: last_update)
    end
  end

  defp assign_success_data(socket, data) do
    assigns = [
      faturamento: assign_faturamento(data),
      objetivo: assign_objetivo(data),
      realizado: assign_realizado(data),
      margem: assign_margem(data),
      cupons: assign_cupons(data),
      ticket: assign_ticket(data),
      objetivo_hoje: assign_objetivo_hoje(data),
      venda_hoje: assign_venda_hoje(data),
      nfs_hoje: assign_nfs_hoje(data),
      devolucao: assign_devolucao(data),
      objetivo_hora: assign_objetivo_hora(data),
      percentual_objetivo_hora: assign_percentual_objetivo_hora(data),
      mix: assign_mix(data),
      desconto: assign_desconto(data),
      activities: generate_activities(data),
      tick: socket.assigns[:tick] || 0,
      last_update: DateTime.utc_now(),
      api_status: :ok
    ]

    assign(socket, assigns)
  end

  defp assign_faturamento(data), do: format_money(data["sale"] || 0.0)
  defp assign_objetivo(data), do: format_money(data["objetive"] || 0.0)
  defp assign_realizado(data), do: format_percent(data["percentualSale"] || 0.0)
  defp assign_margem(data), do: format_percent(calculate_margin(data))
  defp assign_cupons(data), do: data["nfs"] || 0
  defp assign_ticket(data), do: format_money(calculate_ticket(data))
  defp assign_objetivo_hoje(data), do: format_money(data["objetiveToday"] || 0.0)
  defp assign_venda_hoje(data), do: format_money(data["saleToday"] || 0.0)
  defp assign_nfs_hoje(data), do: data["nfsToday"] || 0
  defp assign_devolucao(data), do: format_money(data["devolution"] || 0.0)
  defp assign_objetivo_hora(data), do: format_money(data["objetiveHour"] || 0.0)

  defp assign_percentual_objetivo_hora(data),
    do: format_percent(data["percentualObjetiveHour"] || 0.0)

  defp assign_mix(data), do: data["mix"] || 0
  defp assign_desconto(data), do: format_money(data["discount"] || 0.0)



  defp assign_error_data(socket, reason) do
    assign(socket,
      faturamento: 0,
      objetivo: 0,
      realizado: 0,
      margem: 0,
      cupons: 0,
      ticket: 0,
      objetivo_hoje: 0,
      venda_hoje: 0,
      nfs_hoje: 0,
      devolucao: 0,
      objetivo_hora: 0,
      percentual_objetivo_hora: 0,
      mix: 0,
      desconto: 0,
      activities: [],
      api_status: :error,
      api_error: reason,
      last_update: socket.assigns[:last_update] || nil
    )
  end

  defp generate_activities(data) do
    initial_activities = []

    # Adiciona atividade de meta baseada no percentual de venda
    activities_with_meta =
      if data["percentualSale"] do
        initial_activities ++
          [
            %{
              type: :meta,
              loja: "Loja Principal",
              percent: data["percentualSale"]
            }
          ]
      else
        initial_activities
      end

    # Adiciona atividade de venda do dia
    activities_with_sale =
      if data["saleToday"] && data["saleToday"] > 0 do
        activities_with_meta ++
          [
            %{
              type: :venda,
              user: "Sistema",
              valor: data["saleToday"]
            }
          ]
      else
        activities_with_meta
      end

    # Adiciona atividade de mix de produtos
    final_activities =
      if data["mix"] && data["mix"] > 0 do
        activities_with_sale ++
          [
            %{
              type: :produto,
              marca: "Mix de #{data["mix"]} produtos"
            }
          ]
      else
        activities_with_sale
      end

    final_activities
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-white">
      <!-- Sidebar -->
      <div class="fixed left-0 top-0 h-full w-64 bg-white shadow-sm border-r border-gray-200 flex flex-col z-10">
        <!-- Header -->
        <div class="p-6 border-b border-gray-100">
          <div class="flex items-center space-x-3">
            <div>
              <h2 class="text-lg font-medium text-gray-900">Jurunenese</h2>
              <p class="text-sm text-gray-500">Admin Panel</p>
            </div>
          </div>
        </div>
        <!-- Navigation -->
        <nav class="flex-1 p-4 space-y-1">
          <a
            href="/buscar-pedido"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Buscar Pedido
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg group"
          >
            Dashboard
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Forms
            <span class="ml-auto bg-gray-200 text-gray-700 text-xs px-2 py-1 rounded-full">12</span>
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Submissions
            <span class="ml-auto bg-red-100 text-red-700 text-xs px-2 py-1 rounded-full">3</span>
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Analytics
          </a>
          <div class="border-t border-gray-200 my-4"></div>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Team
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Settings
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Help & Support
          </a>
        </nav>
        <!-- User Profile -->
        <div class="p-4 border-t border-gray-200">
          <div class="flex items-center space-x-3">
            <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-medium">JD</span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-gray-900 truncate">John Doe</p>
              <p class="text-xs text-gray-500 truncate">john@formstack.com</p>
            </div>
            <button class="p-1 text-gray-400 hover:text-gray-600">
            </button>
          </div>
        </div>
      </div>
      <!-- Main Content Area -->
      <div class="flex-1 ml-64 flex flex-col items-center py-12 px-4 sm:px-8 bg-white">
        <div class="flex items-center justify-between w-full max-w-6xl mb-8">
          <h1 class="text-xl font-medium text-gray-900">Dashboard</h1>
          <div class="flex items-center space-x-4">
            <!-- Status da API -->
            <div class="flex items-center space-x-2">
              <div class={[
                "w-3 h-3 rounded-full",
                if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")
              ]} />
              <span class="text-sm text-gray-600">
                {if @api_status == :ok, do: "API Online", else: "API Offline"}
              </span>
            </div>
          </div>
        </div>

    <!-- Cards: Grid responsiva, centralizada, espaçamento amplo -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-8 w-full max-w-7xl mx-auto items-stretch mb-12">
          <.card title="Faturamento" value={@faturamento} subtitle="Líquido" icon_bg="bg-green-50">
            <:icon>
            </:icon>
          </.card>
          <.card title="Realizado" value={@realizado} subtitle="Meta" icon_bg="bg-blue-50">
            <:icon>
            </:icon>
          </.card>
          <.card title="Margem" value={@margem} subtitle="Líquida" icon_bg="bg-yellow-50">
            <:icon>
            </:icon>
          </.card>
          <.card
            title="NFS"
            value={@cupons}
            subtitle={"Ticket Médio " <> @ticket}
            icon_bg="bg-indigo-50"
          >
            <:icon>
            </:icon>
          </.card>
          <.card
            title="Vendas Hoje"
            value={@venda_hoje}
            subtitle={"Meta: " <> @objetivo_hoje}
            icon_bg="bg-pink-50"
          >
            <:icon>
            </:icon>
          </.card>
          <.card
            title="Devoluções"
            value={@devolucao}
            subtitle={"Desconto: " <> @desconto}
            icon_bg="bg-red-50"
          >
            <:icon>
            </:icon>
          </.card>
          <.card
            title="Mix de Produtos"
            value={@mix}
            subtitle="Produtos diferentes"
            icon_bg="bg-purple-50"
          >
            <:icon>
            </:icon>
          </.card>
        </div>

    <!-- Metas & Atividades -->
        <div class="bg-white rounded-xl shadow-lg border border-gray-100 w-full max-w-6xl">
          <div class="p-6 border-b border-gray-100">
            <h2 class="text-base font-medium text-gray-900">Metas & Atividades</h2>
          </div>
          <div class="p-6 space-y-4">
            <%= for activity <- @activities do %>
              <%= case activity do %>
                <% %{type: :meta, loja: loja, percent: percent} -> %>
                  <div class="flex items-center text-sm text-blue-700">
                    <span class="font-medium mr-2">Metas</span>
                    Loja <span class="font-medium ml-1 mr-1"><%= loja %></span>:
                    <span class="ml-1">{percent}% atingida</span>
                  </div>
                <% %{type: :venda, user: user, valor: valor} -> %>
                  <div class="flex items-center text-sm text-green-700">
                    <span class="font-medium mr-2">Venda</span>
                    <span>{user} vendeu</span>
                    <span class="font-medium ml-1">
                      R$ {:erlang.float_to_binary(:erlang.float(valor), decimals: 2)}
                    </span>
                  </div>
                <% %{type: :produto, marca: marca} -> %>
                  <div class="flex items-center text-sm text-yellow-700">
                    <span class="font-medium mr-2">Produto em Alta</span>
                    <span>Marca <span class="font-medium ml-1">{marca}</span></span>
                  </div>
              <% end %>
            <% end %>
          </div>
        </div>

    <!-- Mensagem de erro da API -->
        <%= if @api_status == :error do %>
          <div class="mt-8 bg-red-50 border border-red-200 rounded-lg p-4 w-full max-w-6xl">
            <div class="flex items-center">
              <span class="text-red-800 font-medium">Erro na API:</span>
              <span class="text-red-700 ml-2">{@api_error}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
