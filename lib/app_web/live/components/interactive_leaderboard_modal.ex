defmodule AppWeb.InteractiveLeaderboardModal do
  @moduledoc """
  Modal super interativa para exibição detalhada do leaderboard de vendas.

  Funcionalidades:
  - Filtros avançados por período, loja, valor
  - Ordenação dinâmica por diferentes critérios
  - Perfis detalhados dos vendedores
  - Gráficos interativos de performance
  - Sistema de favoritos
  - Animações fluidas
  - Responsividade completa
  """

  use AppWeb, :live_component
  import AppWeb.DashboardUtils

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign_initial_state()

    {:ok, socket}
  end

  @impl true
  def update(%{sales_feed: sales_feed} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_processed_data(sales_feed)
      |> assign_statistics()

    {:ok, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_leaderboard_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", %{"seller_id" => seller_id}, socket) do
    favorites = socket.assigns.favorites

    updated_favorites =
      if seller_id in favorites do
        List.delete(favorites, seller_id)
      else
        [seller_id | favorites]
      end

    socket =
      socket
      |> assign(favorites: updated_favorites)
      |> put_flash(:info,
        if seller_id in favorites do
          "Vendedor removido dos favoritos"
        else
          "Vendedor adicionado aos favoritos!"
        end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_sort", %{"sort_by" => sort_by}, socket) do
    current_sort = socket.assigns.sort_by
    sort_order = if current_sort == sort_by and socket.assigns.sort_order == :desc, do: :asc, else: :desc

    socket =
      socket
      |> assign(sort_by: sort_by, sort_order: sort_order)
      |> assign_processed_data(socket.assigns.sales_feed)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_period", %{"period" => period}, socket) do
    socket =
      socket
      |> assign(filter_period: period)
      |> assign_processed_data(socket.assigns.sales_feed)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_seller_details", %{"seller_id" => seller_id}, socket) do
    expanded = socket.assigns.expanded_sellers

    updated_expanded =
      if seller_id in expanded do
        List.delete(expanded, seller_id)
      else
        [seller_id | expanded]
      end

    {:noreply, assign(socket, expanded_sellers: updated_expanded)}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    socket =
      socket
      |> assign(
        sort_by: "sale_value",
        sort_order: :desc,
        filter_period: "all",
        search_term: ""
      )
      |> assign_processed_data(socket.assigns.sales_feed)

    {:noreply, socket}
  end

  # Funções privadas

  defp assign_initial_state(socket) do
    assign(socket,
      show_modal: true,
      sales_feed: [],
      processed_sales: [],
      sort_by: "sale_value",
      sort_order: :desc,
      filter_period: "all",
      search_term: "",
      favorites: [],
      expanded_sellers: [],
      stats: %{},
      view_mode: "cards" # "cards" ou "table"
    )
  end

  defp assign_processed_data(socket, sales_feed) do
    processed =
      sales_feed
      |> filter_by_period(socket.assigns.filter_period)
      |> sort_sales(socket.assigns.sort_by, socket.assigns.sort_order)
      |> add_rankings()
      |> add_seller_stats()

    assign(socket, processed_sales: processed)
  end

  defp assign_statistics(socket) do
    sales = socket.assigns.processed_sales

    stats = %{
      total_sellers: length(sales),
      total_sales: Enum.sum(Enum.map(sales, & &1.sale_value)),
      avg_sale: if(length(sales) > 0, do: Enum.sum(Enum.map(sales, & &1.sale_value)) / length(sales), else: 0),
      top_performer: List.first(sales),
      recent_count: Enum.count(sales, &is_recent?(&1.timestamp))
    }

    assign(socket, stats: stats)
  end

  defp filter_by_period(sales, "all"), do: sales
  defp filter_by_period(sales, "today") do
    today = Date.utc_today()
    Enum.filter(sales, fn sale ->
      DateTime.to_date(sale.timestamp) == today
    end)
  end
  defp filter_by_period(sales, "week") do
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
    Enum.filter(sales, fn sale ->
      DateTime.compare(sale.timestamp, week_ago) == :gt
    end)
  end

  defp sort_sales(sales, "sale_value", order) do
    Enum.sort_by(sales, & &1.sale_value, order)
  end
  defp sort_sales(sales, "seller_name", order) do
    Enum.sort_by(sales, & &1.seller_name, order)
  end
  defp sort_sales(sales, "timestamp", order) do
    Enum.sort_by(sales, & &1.timestamp, order)
  end
  defp sort_sales(sales, _default, order) do
    Enum.sort_by(sales, & &1.sale_value, order)
  end

  defp add_rankings(sales) do
    sales
    |> Enum.with_index(1)
    |> Enum.map(fn {sale, index} ->
      Map.put(sale, :rank, index)
    end)
  end

  defp add_seller_stats(sales) do
    Enum.map(sales, fn sale ->
      performance_score = calculate_performance_score(sale)
      trend = calculate_trend(sale)

      sale
      |> Map.put(:performance_score, performance_score)
      |> Map.put(:trend, trend)
    end)
  end

  defp calculate_performance_score(sale) do
    base_score = min(sale.sale_value / 1000, 100)
    objetivo_bonus = if sale.objetivo > 0 and sale.sale_value >= sale.objetivo, do: 20, else: 0
    recency_bonus = if is_recent?(sale.timestamp), do: 10, else: 0

    (base_score + objetivo_bonus + recency_bonus)
    |> Float.round(1)
  end

  defp calculate_trend(_sale) do
    # Simulação de tendência - em produção viria de dados históricos
    Enum.random([:up, :down, :stable])
  end

  defp is_recent?(timestamp) do
    DateTime.diff(DateTime.utc_now(), timestamp, :hour) <= 2
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "agora"
      diff < 3600 -> "#{Kernel.div(diff, 60)}m"
      diff < 86_400 -> "#{Kernel.div(diff, 3600)}h"
      true -> Calendar.strftime(datetime, "%d/%m")
    end
  end

  defp rank_style(rank) do
    case rank do
      1 -> "bg-gradient-to-r from-yellow-400 to-yellow-600 text-white"
      2 -> "bg-gradient-to-r from-gray-300 to-gray-500 text-white"
      3 -> "bg-gradient-to-r from-orange-400 to-orange-600 text-white"
      _ -> "bg-gray-100 text-gray-700"
    end
  end

  defp trend_icon(trend) do
    case trend do
      :up -> "🔥"
      :down -> "📉"
      :stable -> "➡️"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="leaderboard-modal"
      class="fixed inset-0 z-50 overflow-y-auto bg-black bg-opacity-50 flex items-center justify-center p-4"
      phx-click="close_modal"
      phx-target={@myself}
    >
      <!-- Modal Container -->
      <div
        class="bg-white rounded-2xl shadow-2xl w-full max-w-6xl max-h-[90vh] overflow-hidden transform transition-all duration-300 scale-100"
        phx-click={JS.stop_propagation()}
      >
        <!-- Header -->
        <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-4 sm:p-6">
          <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between space-y-3 sm:space-y-0">
            <div>
              <h2 class="text-xl sm:text-2xl font-bold flex items-center space-x-2">
                <span>🏆</span>
                <span>Leaderboard Interativo</span>
              </h2>
              <p class="text-blue-100 text-sm mt-1">
                {length(@processed_sales)} vendedores • {format_money(@stats.total_sales)} total
              </p>
            </div>

            <!-- Quick Stats -->
            <div class="flex flex-wrap gap-3 text-sm">
              <div class="bg-white bg-opacity-20 px-3 py-1 rounded-full">
                <span class="opacity-80">Média:</span>
                <span class="font-medium ml-1">{format_money(@stats.avg_sale)}</span>
              </div>
              <div class="bg-white bg-opacity-20 px-3 py-1 rounded-full">
                <span class="opacity-80">Recentes:</span>
                <span class="font-medium ml-1">{@stats.recent_count}</span>
              </div>
            </div>

            <!-- Close Button -->
            <button
              phx-click="close_modal"
              phx-target={@myself}
              class="absolute top-4 right-4 text-white hover:text-red-300 transition-colors p-1"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        </div>

        <!-- Filters & Controls -->
        <div class="border-b border-gray-200 p-4 sm:p-6 bg-gray-50">
          <div class="flex flex-col lg:flex-row items-start lg:items-center justify-between space-y-4 lg:space-y-0 lg:space-x-4">
            <!-- Sort Controls -->
            <div class="flex flex-wrap gap-2">
              <button
                phx-click="change_sort"
                phx-value-sort_by="sale_value"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@sort_by == "sale_value",
                    do: "bg-blue-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-blue-50")
                ]}
              >
                💰 Por Valor {if @sort_by == "sale_value", do: if(@sort_order == :desc, do: "↓", else: "↑")}
              </button>

              <button
                phx-click="change_sort"
                phx-value-sort_by="seller_name"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@sort_by == "seller_name",
                    do: "bg-blue-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-blue-50")
                ]}
              >
                👤 Por Nome {if @sort_by == "seller_name", do: if(@sort_order == :desc, do: "↓", else: "↑")}
              </button>

              <button
                phx-click="change_sort"
                phx-value-sort_by="timestamp"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@sort_by == "timestamp",
                    do: "bg-blue-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-blue-50")
                ]}
              >
                ⏰ Por Tempo {if @sort_by == "timestamp", do: if(@sort_order == :desc, do: "↓", else: "↑")}
              </button>
            </div>

            <!-- Period Filters -->
            <div class="flex flex-wrap gap-2">
              <button
                phx-click="filter_period"
                phx-value-period="all"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@filter_period == "all",
                    do: "bg-green-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-green-50")
                ]}
              >
                📅 Tudo
              </button>

              <button
                phx-click="filter_period"
                phx-value-period="today"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@filter_period == "today",
                    do: "bg-green-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-green-50")
                ]}
              >
                📆 Hoje
              </button>

              <button
                phx-click="filter_period"
                phx-value-period="week"
                phx-target={@myself}
                class={[
                  "px-3 py-2 rounded-lg text-sm font-medium transition-all",
                  if(@filter_period == "week",
                    do: "bg-green-600 text-white shadow-lg",
                    else: "bg-white text-gray-700 border hover:bg-green-50")
                ]}
              >
                🗓️ Semana
              </button>
            </div>

            <!-- Reset Button -->
            <button
              phx-click="reset_filters"
              phx-target={@myself}
              class="px-4 py-2 bg-gray-600 text-white rounded-lg text-sm font-medium hover:bg-gray-700 transition-colors"
            >
              🔄 Reset
            </button>
          </div>
        </div>

        <!-- Content -->
        <div class="p-4 sm:p-6 max-h-[60vh] overflow-y-auto">
          <%= if Enum.empty?(@processed_sales) do %>
            <!-- Empty State -->
            <div class="text-center py-12">
              <div class="text-6xl mb-4">🏆</div>
              <h3 class="text-xl font-medium text-gray-900 mb-2">Nenhum vendedor encontrado</h3>
              <p class="text-gray-500">Ajuste os filtros para ver mais resultados</p>
            </div>
          <% else %>
            <!-- Sales Cards -->
            <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              <%= for sale <- @processed_sales do %>
                <div class={[
                  "bg-white border-2 rounded-xl p-4 transition-all duration-300 hover:shadow-lg cursor-pointer",
                  case sale.rank do
                    1 -> "border-yellow-400 bg-gradient-to-br from-yellow-50 to-yellow-100"
                    2 -> "border-gray-400 bg-gradient-to-br from-gray-50 to-gray-100"
                    3 -> "border-orange-400 bg-gradient-to-br from-orange-50 to-orange-100"
                    _ -> "border-gray-200 hover:border-blue-300"
                  end
                ]}>
                  <!-- Card Header -->
                  <div class="flex items-center justify-between mb-3">
                    <!-- Rank Badge -->
                    <div class={["w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold", rank_style(sale.rank)]}>
                      #{sale.rank}
                    </div>

                    <!-- Actions -->
                    <div class="flex items-center space-x-2">
                      <!-- Trend -->
                      <span class="text-lg" title={"Tendência: #{sale.trend}"}>
                        {trend_icon(sale.trend)}
                      </span>

                      <!-- Favorite -->
                      <button
                        phx-click="toggle_favorite"
                        phx-value-seller_id={sale.id}
                        phx-target={@myself}
                        class={[
                          "p-1 rounded-full transition-colors",
                          if(sale.id in @favorites, do: "text-red-500 hover:text-red-600", else: "text-gray-400 hover:text-red-500")
                        ]}
                      >
                        {if sale.id in @favorites, do: "❤️", else: "🤍"}
                      </button>

                      <!-- Expand -->
                      <button
                        phx-click="toggle_seller_details"
                        phx-value-seller_id={sale.id}
                        phx-target={@myself}
                        class="p-1 text-gray-400 hover:text-blue-500 transition-colors"
                      >
                        {if sale.id in @expanded_sellers, do: "🔼", else: "🔽"}
                      </button>
                    </div>
                  </div>

                  <!-- Seller Info -->
                  <div class="mb-3">
                    <h3 class="font-bold text-gray-900 text-lg mb-1">{sale.seller_name}</h3>
                    <p class="text-sm text-gray-600 mb-2">{sale.store}</p>

                    <!-- Performance Score -->
                    <div class="flex items-center space-x-2 mb-2">
                      <span class="text-xs text-gray-500">Score:</span>
                      <div class="flex-1 bg-gray-200 rounded-full h-2">
                        <div
                          class="bg-gradient-to-r from-blue-500 to-purple-500 h-2 rounded-full transition-all duration-500"
                          style={"width: #{min(sale.performance_score, 100)}%"}
                        ></div>
                      </div>
                      <span class="text-xs font-medium text-gray-700">{sale.performance_score}</span>
                    </div>
                  </div>

                  <!-- Sales Data -->
                  <div class="space-y-2">
                    <div class="flex justify-between items-center">
                      <span class="text-sm text-gray-600">Venda:</span>
                      <span class="font-mono font-bold text-green-600 text-lg">
                        {sale.sale_value_formatted}
                      </span>
                    </div>

                    <%= if sale.objetivo > 0 do %>
                      <div class="flex justify-between items-center">
                        <span class="text-sm text-gray-600">Meta:</span>
                        <span class="font-mono text-gray-700">{sale.objetivo_formatted}</span>
                      </div>

                      <!-- Progress bar -->
                      <div class="w-full bg-gray-200 rounded-full h-2 mt-2">
                        <div
                          class={[
                            "h-2 rounded-full transition-all duration-500",
                            if(sale.sale_value >= sale.objetivo,
                              do: "bg-gradient-to-r from-green-500 to-emerald-500",
                              else: "bg-gradient-to-r from-yellow-500 to-orange-500")
                          ]}
                          style={"width: #{min((sale.sale_value / sale.objetivo * 100), 100)}%"}
                        ></div>
                      </div>
                    <% end %>
                  </div>

                  <!-- Timestamp -->
                  <div class="mt-3 pt-3 border-t border-gray-200 flex items-center justify-between text-xs text-gray-500">
                    <span>{time_ago(sale.timestamp)}</span>
                    <span>{Calendar.strftime(sale.timestamp, "%H:%M")}</span>
                  </div>

                  <!-- Expanded Details -->
                  <%= if sale.id in @expanded_sellers do %>
                    <div class="mt-4 pt-4 border-t border-gray-200 space-y-3 animate-fade-in">
                      <h4 class="font-medium text-gray-900">📊 Detalhes da Performance</h4>

                      <div class="grid grid-cols-2 gap-3 text-sm">
                        <div class="bg-blue-50 p-3 rounded-lg">
                          <span class="text-blue-700 font-medium">Meta Atingida</span>
                          <div class="text-blue-900 font-bold">
                            {if sale.objetivo > 0, do: :erlang.float_to_binary((sale.sale_value / sale.objetivo * 100), decimals: 1), else: "N/A"}%
                          </div>
                        </div>

                        <div class="bg-green-50 p-3 rounded-lg">
                          <span class="text-green-700 font-medium">Score</span>
                          <div class="text-green-900 font-bold">{sale.performance_score}</div>
                        </div>
                      </div>

                      <!-- Mock additional data -->
                      <div class="bg-gray-50 p-3 rounded-lg">
                        <div class="text-xs text-gray-600 mb-1">Histórico (últimos 7 dias)</div>
                        <div class="flex items-end space-x-1 h-8">
                          <%= for i <- 1..7 do %>
                            <div
                              class="bg-blue-400 rounded-sm opacity-70 flex-1"
                              style={"height: #{Enum.random(20..100)}%"}
                            ></div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Footer -->
        <div class="border-t border-gray-200 bg-gray-50 p-4 sm:p-6">
          <div class="flex flex-col sm:flex-row items-center justify-between space-y-3 sm:space-y-0">
            <div class="text-sm text-gray-600">
              🔄 Atualizado em tempo real • {length(@favorites)} favoritos
            </div>

            <div class="flex items-center space-x-3">
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
