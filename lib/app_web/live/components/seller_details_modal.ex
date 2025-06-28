defmodule AppWeb.SellerDetailsModal do
  @moduledoc """
  Modal para exibir detalhes completos de um vendedor específico vindos da API real.

  Funcionalidades:
  - Busca dados reais da API do supervisor
  - Perfil completo do vendedor com dados da API
  - Estatísticas detalhadas de performance
  - Performance hoje e por hora
  - Pré-vendas e informações adicionais
  - Seletor de supervisores
  """

  use AppWeb, :live_component
  import AppWeb.DashboardUtils

  @api_base_url "http://10.1.1.108:8065/api/v1/dashboard/sale"

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(
        api_data: nil,
        loading: true,
        error: nil,
        selected_supervisor: 12,
        available_supervisors: [
          %{id: 12, name: "Supervisor 12"},
          %{id: 13, name: "Supervisor 13"},
          %{id: 14, name: "Supervisor 14"},
          %{id: 15, name: "Supervisor 15"}
        ],
        selected_seller: nil,
        sellers_list: []
      )

    {:ok, socket}
  end

  @impl true
  def update(%{seller_data: seller_data} = assigns, socket) do
    # Busca dados da API baseado no seller_data inicial
    supervisor_id = extract_supervisor_id(seller_data)

    socket =
      socket
      |> assign(assigns)
      |> assign(selected_supervisor: supervisor_id)
      |> fetch_api_data(supervisor_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_seller_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_supervisor", %{"supervisor_id" => supervisor_id}, socket) do
    supervisor_id = String.to_integer(supervisor_id)

    socket =
      socket
      |> assign(selected_supervisor: supervisor_id, loading: true, error: nil)
      |> fetch_api_data(supervisor_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_seller", %{"seller_id" => seller_id}, socket) do
    seller_id = String.to_integer(seller_id)
    selected_seller = Enum.find(socket.assigns.sellers_list, &(&1.sellerId == seller_id))

    {:noreply, assign(socket, selected_seller: selected_seller)}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    socket =
      socket
      |> assign(loading: true, error: nil)
      |> fetch_api_data(socket.assigns.selected_supervisor)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    is_favorite = !Map.get(socket.assigns, :is_favorite, false)

    socket =
      socket
      |> assign(is_favorite: is_favorite)
      |> put_flash(:info,
        if is_favorite do
          "Vendedor adicionado aos favoritos!"
        else
          "Vendedor removido dos favoritos"
        end)

    {:noreply, socket}
  end

  # Funções privadas

  defp fetch_api_data(socket, supervisor_id) do
    # Faz a chamada HTTP para buscar dados reais
    case make_api_request(supervisor_id) do
      {:ok, data} ->
        sellers_list = if is_list(data), do: data, else: [data]
        selected_seller = List.first(sellers_list)

        assign(socket,
          api_data: data,
          sellers_list: sellers_list,
          selected_seller: selected_seller,
          loading: false,
          error: nil
        )

      {:error, reason} ->
        assign(socket,
          api_data: nil,
          sellers_list: [],
          selected_seller: nil,
          loading: false,
          error: reason
        )
    end
  end

  defp make_api_request(supervisor_id) do
    url = "#{@api_base_url}/#{supervisor_id}"

    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "Erro ao decodificar resposta da API"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{reason}"}

      {:error, reason} ->
        {:error, "Erro inesperado: #{inspect(reason)}"}
    end
  end

  defp extract_supervisor_id(_seller_data) do
    # Por padrão usa supervisor 12, mas pode ser extraído dos dados se necessário
    12
  end

  defp format_currency(value) when is_number(value) do
    :erlang.float_to_binary(value, decimals: 2)
    |> String.replace(".", ",")
    |> then(&("R$ " <> &1))
  end
  defp format_currency(_), do: "R$ 0,00"

  defp format_percentage(value) when is_number(value) do
    :erlang.float_to_binary(value, decimals: 1)
    |> String.replace(".", ",")
    |> then(&(&1 <> "%"))
  end
  defp format_percentage(_), do: "0,0%"

  defp get_performance_color(percentage) when is_number(percentage) do
    cond do
      percentage >= 100 -> "text-green-600"
      percentage >= 80 -> "text-yellow-600"
      true -> "text-red-600"
    end
  end
  defp get_performance_color(_), do: "text-gray-600"

  defp get_performance_badge(percentage) when is_number(percentage) do
    cond do
      percentage >= 100 ->
        %{label: "Meta Atingida", color: "bg-green-100 text-green-800"}
      percentage >= 80 ->
        %{label: "Próximo da Meta", color: "bg-yellow-100 text-yellow-800"}
      true ->
        %{label: "Abaixo da Meta", color: "bg-red-100 text-red-800"}
    end
  end
  defp get_performance_badge(_), do: %{label: "Sem Dados", color: "bg-gray-100 text-gray-800"}

  defp clean_seller_name(name) when is_binary(name) do
    name
    |> String.replace(~r/^CN - |^CX - |^CRED - |^CN-|^CX-/, "")
    |> String.trim()
  end
  defp clean_seller_name(_), do: "Nome não disponível"

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="seller-details-modal"
      class="fixed inset-0 z-50 overflow-y-auto bg-black bg-opacity-50 flex items-center justify-center p-4"
      phx-click="close_modal"
      phx-target={@myself}
    >
      <!-- Modal Container -->
      <div
        class="bg-white rounded-2xl shadow-2xl w-full max-w-5xl max-h-[90vh] overflow-hidden transform transition-all duration-300 scale-100"
        phx-click={JS.stop_propagation()}
      >
        <!-- Header -->
        <div class="bg-gradient-to-r from-indigo-600 to-purple-600 text-white p-6">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-2xl font-bold flex items-center space-x-2">
                <span>📊</span>
                <span>Dashboard de Vendedor</span>
              </h2>
              <p class="text-indigo-100 text-sm mt-1">
                Dados em tempo real da API de vendas
              </p>
            </div>

            <!-- Controls -->
            <div class="flex items-center space-x-3">
              <!-- Refresh Button -->
              <button
                phx-click="refresh_data"
                phx-target={@myself}
                class="p-2 bg-white bg-opacity-20 rounded-full hover:bg-opacity-30 transition-colors"
                title="Atualizar dados"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
              </button>

              <!-- Close Button -->
              <button
                phx-click="close_modal"
                phx-target={@myself}
                class="text-white hover:text-red-300 transition-colors p-1"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Content -->
        <div class="p-6 max-h-[70vh] overflow-y-auto">
          <%= if @loading do %>
            <!-- Loading State -->
            <div class="space-y-6">
              <div class="animate-pulse">
                <div class="h-8 bg-gray-200 rounded w-3/4 mb-4"></div>
                <div class="h-4 bg-gray-200 rounded w-1/2 mb-6"></div>
                <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
                  <%= for _ <- 1..4 do %>
                    <div class="h-20 bg-gray-200 rounded"></div>
                  <% end %>
                </div>
                <div class="h-32 bg-gray-200 rounded"></div>
              </div>
            </div>

          <% else %>
            <%= if @error do %>
              <!-- Error State -->
              <div class="text-center py-8">
                <div class="w-16 h-16 mx-auto mb-4 text-red-500">
                  <svg fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                  </svg>
                </div>
                <h3 class="text-xl font-medium text-gray-900 mb-2">Erro ao carregar dados</h3>
                <p class="text-gray-600 mb-4">{@error}</p>
                <button
                  phx-click="refresh_data"
                  phx-target={@myself}
                  class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                >
                  🔄 Tentar Novamente
                </button>
              </div>

            <% else %>
              <!-- Supervisor Selector -->
              <div class="bg-gray-50 p-4 rounded-lg mb-6">
                <h3 class="font-medium text-gray-900 mb-3">Selecionar Supervisor:</h3>
                <div class="flex flex-wrap gap-2">
                  <%= for supervisor <- @available_supervisors do %>
                    <button
                      phx-click="change_supervisor"
                      phx-value-supervisor_id={supervisor.id}
                      phx-target={@myself}
                      class={[
                        "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
                        if(@selected_supervisor == supervisor.id,
                          do: "bg-blue-600 text-white",
                          else: "bg-white text-gray-700 border hover:bg-blue-50")
                      ]}
                    >
                      {supervisor.name}
                    </button>
                  <% end %>
                </div>
              </div>

              <!-- Sellers List -->
              <%= if length(@sellers_list) > 0 do %>
                <div class="bg-white border border-gray-200 rounded-lg p-4 mb-6">
                  <h3 class="font-medium text-gray-900 mb-3">Selecionar Vendedor:</h3>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2 max-h-60 overflow-y-auto">
                    <%= for seller <- @sellers_list do %>
                      <button
                        phx-click="select_seller"
                        phx-value-seller_id={seller.sellerId}
                        phx-target={@myself}
                        class={[
                          "text-left p-3 rounded border transition-colors",
                          if(@selected_seller && @selected_seller.sellerId == seller.sellerId,
                            do: "bg-blue-50 border-blue-300",
                            else: "bg-gray-50 border-gray-200 hover:bg-blue-50")
                        ]}
                      >
                        <div class="font-medium text-sm">
                          {clean_seller_name(seller.sellerName)}
                        </div>
                        <div class="text-xs text-gray-500">
                          {format_percentage(seller.percentualObjective)} da meta
                        </div>
                      </button>
                    <% end %>
                  </div>
                </div>

                <!-- Selected Seller Details -->
                <%= if @selected_seller do %>
                  <div class="space-y-6">
                    <!-- Seller Header -->
                    <div class="bg-white border border-gray-200 rounded-xl p-6">
                      <div class="flex items-start justify-between mb-4">
                        <div class="space-y-2">
                          <h3 class="text-2xl font-bold text-gray-900">
                            {clean_seller_name(@selected_seller.sellerName)}
                          </h3>
                          <div class="flex items-center gap-2 text-sm text-gray-600">
                            <span>🏪 {@selected_seller.store}</span>
                            <span class="text-gray-400">•</span>
                            <span>ID: {@selected_seller.sellerId}</span>
                          </div>
                        </div>
                        <div class={["px-3 py-1 rounded-full text-sm font-medium", get_performance_badge(@selected_seller.percentualObjective).color]}>
                          {get_performance_badge(@selected_seller.percentualObjective).label}
                        </div>
                      </div>

                      <!-- Performance Principal -->
                      <div class="space-y-3">
                        <div class="flex items-center justify-between">
                          <h4 class="font-medium text-gray-900 flex items-center gap-2">
                            🎯 Performance de Vendas
                          </h4>
                          <span class={["font-bold text-lg", get_performance_color(@selected_seller.percentualObjective)]}>
                            {format_percentage(@selected_seller.percentualObjective)}
                          </span>
                        </div>

                        <div class="w-full bg-gray-200 rounded-full h-3">
                          <div
                            class="bg-gradient-to-r from-blue-500 to-purple-500 h-3 rounded-full transition-all duration-500"
                            style={"width: #{min(@selected_seller.percentualObjective, 100)}%"}
                          ></div>
                        </div>

                        <div class="grid grid-cols-2 gap-4 text-sm">
                          <div>
                            <span class="text-gray-600">Vendido:</span>
                            <p class="font-bold text-green-600 text-lg">{format_currency(@selected_seller.saleValue)}</p>
                          </div>
                          <div>
                            <span class="text-gray-600">Meta:</span>
                            <p class="font-bold text-lg">{format_currency(@selected_seller.objetivo)}</p>
                          </div>
                        </div>

                        <%= if @selected_seller.dif != 0 do %>
                          <div class={[
                            "flex items-center gap-2 p-3 rounded-lg",
                            if(@selected_seller.dif > 0, do: "bg-green-50", else: "bg-red-50")
                          ]}>
                            <span class="text-lg">
                              {if @selected_seller.dif > 0, do: "📈", else: "📉"}
                            </span>
                            <span class="text-sm">
                              {if @selected_seller.dif > 0, do: "Acima da meta em ", else: "Faltam "}
                              <span class={[
                                "font-bold",
                                if(@selected_seller.dif > 0, do: "text-green-600", else: "text-red-600")
                              ]}>
                                {format_currency(abs(@selected_seller.dif))}
                              </span>
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <!-- Métricas Cards -->
                    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                      <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 text-center">
                        <div class="text-2xl mb-1">🛒</div>
                        <p class="text-xs text-gray-600 mb-1">Vendas</p>
                        <p class="font-bold text-blue-600">{@selected_seller.qtdeInvoice}</p>
                      </div>

                      <div class="bg-green-50 border border-green-200 rounded-lg p-4 text-center">
                        <div class="text-2xl mb-1">💰</div>
                        <p class="text-xs text-gray-600 mb-1">Ticket Médio</p>
                        <p class="font-bold text-green-600">{format_currency(@selected_seller.ticket)}</p>
                      </div>

                      <div class="bg-purple-50 border border-purple-200 rounded-lg p-4 text-center">
                        <div class="text-2xl mb-1">🎯</div>
                        <p class="text-xs text-gray-600 mb-1">Mix</p>
                        <p class="font-bold text-purple-600">{@selected_seller.mix}</p>
                      </div>

                      <div class="bg-orange-50 border border-orange-200 rounded-lg p-4 text-center">
                        <div class="text-2xl mb-1">📅</div>
                        <p class="text-xs text-gray-600 mb-1">Dias Úteis</p>
                        <p class="font-bold text-orange-600">
                          {@selected_seller.qtdeDays}/{@selected_seller.qtdeDaysMonth}
                        </p>
                      </div>
                    </div>

                    <!-- Performance Hoje -->
                    <div class="bg-white border border-gray-200 rounded-xl p-6">
                      <h4 class="font-medium text-gray-900 flex items-center gap-2 mb-4">
                        ⏰ Performance Hoje
                      </h4>

                      <div class="grid grid-cols-2 gap-4 mb-4">
                        <div>
                          <span class="text-sm text-gray-600">Meta Hoje</span>
                          <p class="font-bold text-lg">{format_currency(@selected_seller.objetiveToday)}</p>
                        </div>
                        <div>
                          <span class="text-sm text-gray-600">Vendido Hoje</span>
                          <p class="font-bold text-green-600 text-lg">{format_currency(@selected_seller.saleToday)}</p>
                        </div>
                      </div>

                      <%= if @selected_seller.objetiveToday > 0 do %>
                        <div class="space-y-2">
                          <div class="w-full bg-gray-200 rounded-full h-2">
                            <div
                              class="bg-gradient-to-r from-green-500 to-emerald-500 h-2 rounded-full transition-all duration-500"
                              style={"width: #{min((@selected_seller.saleToday / @selected_seller.objetiveToday) * 100, 100)}%"}
                            ></div>
                          </div>
                          <div class="text-xs text-gray-600 text-center">
                            {format_percentage((@selected_seller.saleToday / @selected_seller.objetiveToday) * 100)} da meta diária
                          </div>
                        </div>
                      <% end %>
                    </div>

                    <!-- Performance por Hora -->
                    <%= if @selected_seller.percentualObjectiveHour > 0 do %>
                      <div class="bg-white border border-gray-200 rounded-xl p-6">
                        <h4 class="font-medium text-gray-900 flex items-center gap-2 mb-4">
                          ⏱️ Performance por Hora
                        </h4>
                        <div class="grid grid-cols-2 gap-4">
                          <div>
                            <span class="text-sm text-gray-600">Meta/Hora:</span>
                            <p class="font-bold">{format_currency(@selected_seller.objetiveHour)}</p>
                          </div>
                          <div>
                            <span class="text-sm text-gray-600">Performance:</span>
                            <p class={["font-bold", get_performance_color(@selected_seller.percentualObjectiveHour)]}>
                              {format_percentage(@selected_seller.percentualObjectiveHour)}
                            </p>
                          </div>
                        </div>
                      </div>
                    <% end %>

                    <!-- Pré-vendas -->
                    <%= if @selected_seller.preSaleQtde > 0 do %>
                      <div class="bg-indigo-50 border border-indigo-200 rounded-xl p-6">
                        <h4 class="font-bold text-indigo-900 mb-4">📋 Pré-vendas</h4>
                        <div class="grid grid-cols-2 gap-4">
                          <div>
                            <span class="text-indigo-600 text-sm">Quantidade:</span>
                            <p class="font-bold">{@selected_seller.preSaleQtde}</p>
                          </div>
                          <div>
                            <span class="text-indigo-600 text-sm">Valor:</span>
                            <p class="font-bold">{format_currency(@selected_seller.preSaleValue)}</p>
                          </div>
                        </div>
                      </div>
                    <% end %>

                    <!-- Informações Adicionais -->
                    <div class="bg-gray-50 rounded-xl p-6">
                      <h4 class="font-medium text-gray-900 mb-4">📊 Informações Adicionais</h4>
                      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                        <div>
                          <span class="text-gray-600">Devoluções:</span>
                          <p class="font-medium">{format_currency(@selected_seller.devolution)}</p>
                        </div>
                        <div>
                          <span class="text-gray-600">Desconto:</span>
                          <p class="font-medium">{format_percentage(@selected_seller.percentOff)}</p>
                        </div>
                        <div>
                          <span class="text-gray-600">NFs Hoje:</span>
                          <p class="font-medium">{@selected_seller.qtdeInvoiceDay}</p>
                        </div>
                        <div>
                          <span class="text-gray-600">Preço Lista:</span>
                          <p class="font-medium">{format_currency(@selected_seller.listPrice)}</p>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% else %>
                <!-- No Data -->
                <div class="text-center py-8">
                  <div class="text-6xl mb-4">📊</div>
                  <h3 class="text-xl font-medium text-gray-900 mb-2">Nenhum dado encontrado</h3>
                  <p class="text-gray-500">Não há vendedores para o supervisor selecionado</p>
                </div>
              <% end %>
            <% end %>
          <% end %>
        </div>

        <!-- Footer -->
        <div class="border-t border-gray-200 bg-gray-50 p-4">
          <div class="flex flex-col sm:flex-row items-center justify-between space-y-2 sm:space-y-0">
            <div class="text-sm text-gray-600">
              🔄 Conectado à API: {@api_base_url}/{@selected_supervisor}
              <%= if @selected_seller do %>
                • Vendedor: {clean_seller_name(@selected_seller.sellerName)}
              <% end %>
            </div>
            <div class="flex items-center space-x-3">
              <button
                phx-click="refresh_data"
                phx-target={@myself}
                class="px-3 py-1 bg-blue-100 text-blue-700 rounded text-xs hover:bg-blue-200 transition-colors"
              >
                🔄 Atualizar
              </button>
              <button
                phx-click="close_modal"
                phx-target={@myself}
                class="px-4 py-2 bg-gray-600 text-white rounded-lg text-sm font-medium hover:bg-gray-700 transition-colors"
              >
                Fechar
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
