defmodule AppWeb.SellerDetailsModal do
  @moduledoc """
  Modal para exibir detalhes completos de um vendedor específico.

  Funcionalidades:
  - Perfil completo do vendedor
  - Estatísticas detalhadas de performance
  - Gráficos de histórico e tendências
  - Comparação com metas
  - Histórico de vendas
  - Badges e conquistas
  """

  use AppWeb, :live_component
  import AppWeb.DashboardUtils

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{seller_data: seller_data} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_seller_stats(seller_data)
      |> assign_seller_history(seller_data)
      |> assign_achievements(seller_data)

    {:ok, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_seller_modal})
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
          "#{socket.assigns.seller_data.seller_name} adicionado aos favoritos!"
        else
          "#{socket.assigns.seller_data.seller_name} removido dos favoritos"
        end)

    {:noreply, socket}
  end

  # Funções privadas

  defp assign_seller_stats(socket, seller_data) do
    # Calcula estatísticas do vendedor
    performance_score = calculate_performance_score(seller_data)
    goal_percentage = calculate_goal_percentage(seller_data)
    rank_position = calculate_rank_position(seller_data)
    efficiency_score = calculate_efficiency_score(seller_data)

    stats = %{
      performance_score: performance_score,
      goal_percentage: goal_percentage,
      rank_position: rank_position,
      efficiency_score: efficiency_score,
      trend: calculate_trend(seller_data),
      is_top_performer: rank_position <= 3,
      is_goal_achieved: goal_percentage >= 100
    }

    assign(socket, seller_stats: stats)
  end

  defp assign_seller_history(socket, _seller_data) do
    # Simula histórico de vendas dos últimos 30 dias
    history =
      1..30
      |> Enum.map(fn day ->
        %{
          day: day,
          sales: Enum.random(0..15000),
          date: Date.add(Date.utc_today(), -day),
          goal: Enum.random(8000..12000)
        }
      end)
      |> Enum.reverse()

    assign(socket, seller_history: history)
  end

  defp assign_achievements(socket, seller_data) do
    # Simula conquistas baseadas na performance
    base_achievements = [
      %{
        title: "Primeira Venda",
        description: "Realizou sua primeira venda",
        icon: "🎯",
        earned: true,
        date: "15/05/2024"
      },
      %{
        title: "Meta Mensal",
        description: "Atingiu a meta do mês",
        icon: "🏆",
        earned: seller_data.sale_value >= (seller_data.objetivo || 0),
        date: if(seller_data.sale_value >= (seller_data.objetivo || 0), do: "Hoje", else: nil)
      },
      %{
        title: "Top 3",
        description: "Ficou entre os 3 melhores",
        icon: "🥇",
        earned: socket.assigns.seller_stats.rank_position <= 3,
        date: if(socket.assigns.seller_stats.rank_position <= 3, do: "Hoje", else: nil)
      },
      %{
        title: "Vendedor do Dia",
        description: "Maior venda do dia",
        icon: "⭐",
        earned: socket.assigns.seller_stats.rank_position == 1,
        date: if(socket.assigns.seller_stats.rank_position == 1, do: "Hoje", else: nil)
      },
      %{
        title: "Consistência",
        description: "30 dias consecutivos vendendo",
        icon: "💪",
        earned: Enum.random([true, false]),
        date: if(Enum.random([true, false]), do: "28/12/2024", else: nil)
      }
    ]

    assign(socket, achievements: base_achievements)
  end

  defp calculate_performance_score(seller_data) do
    base_score = min(seller_data.sale_value / 1000, 100)
    objetivo_bonus = if seller_data.objetivo > 0 and seller_data.sale_value >= seller_data.objetivo, do: 20, else: 0
    recency_bonus = if is_recent?(seller_data.timestamp), do: 10, else: 0

    (base_score + objetivo_bonus + recency_bonus)
    |> Float.round(1)
  end

  defp calculate_goal_percentage(seller_data) do
    if seller_data.objetivo > 0 do
      (seller_data.sale_value / seller_data.objetivo * 100)
      |> Float.round(1)
    else
      0.0
    end
  end

  defp calculate_rank_position(_seller_data) do
    # Em produção, viria do ranking real
    Enum.random(1..10)
  end

  defp calculate_efficiency_score(seller_data) do
    # Simula score de eficiência baseado em tempo x valor
    time_factor = DateTime.diff(DateTime.utc_now(), seller_data.timestamp, :hour)
    efficiency = if time_factor > 0, do: seller_data.sale_value / time_factor, else: seller_data.sale_value
    min(efficiency / 100, 100) |> Float.round(1)
  end

  defp calculate_trend(_seller_data) do
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

  defp trend_color(trend) do
    case trend do
      :up -> "text-green-500"
      :down -> "text-red-500"
      :stable -> "text-yellow-500"
    end
  end

  defp trend_icon(trend) do
    case trend do
      :up -> "📈"
      :down -> "📉"
      :stable -> "➡️"
    end
  end

  defp rank_badge(rank) do
    case rank do
      1 -> %{icon: "🥇", color: "bg-yellow-500", text: "1º Lugar"}
      2 -> %{icon: "🥈", color: "bg-gray-400", text: "2º Lugar"}
      3 -> %{icon: "🥉", color: "bg-orange-500", text: "3º Lugar"}
      _ -> %{icon: "🏷️", color: "bg-blue-500", text: "#{rank}º Lugar"}
    end
  end

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
        class="bg-white rounded-2xl shadow-2xl w-full max-w-4xl max-h-[90vh] overflow-hidden transform transition-all duration-300 scale-100"
        phx-click={JS.stop_propagation()}
      >
        <!-- Header com perfil do vendedor -->
        <div class="bg-gradient-to-r from-indigo-600 to-purple-600 text-white p-6">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <!-- Avatar do vendedor -->
              <div class="w-16 h-16 bg-white bg-opacity-20 rounded-full flex items-center justify-center text-2xl font-bold">
                {String.first(@seller_data.seller_name)}
              </div>

              <div>
                <h2 class="text-2xl font-bold">{@seller_data.seller_name}</h2>
                <p class="text-indigo-100">{@seller_data.store}</p>
                <div class="flex items-center space-x-2 mt-1">
                  <span class={["text-sm", trend_color(@seller_stats.trend)]}>{trend_icon(@seller_stats.trend)}</span>
                  <span class="text-indigo-100 text-sm">Tendência: {@seller_stats.trend}</span>
                </div>
              </div>
            </div>

            <!-- Rank e Favorite -->
            <div class="flex items-center space-x-3">
              <!-- Rank Badge -->
              <div class={["px-3 py-1 rounded-full text-white text-sm font-medium", rank_badge(@seller_stats.rank_position).color]}>
                {rank_badge(@seller_stats.rank_position).icon} {rank_badge(@seller_stats.rank_position).text}
              </div>

              <!-- Favorite Button -->
              <button
                phx-click="toggle_favorite"
                phx-target={@myself}
                class="p-2 bg-white bg-opacity-20 rounded-full hover:bg-opacity-30 transition-colors"
              >
                {if Map.get(assigns, :is_favorite, false), do: "❤️", else: "🤍"}
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
          <!-- Stats Cards -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <!-- Venda Atual -->
            <div class="bg-green-50 border border-green-200 rounded-xl p-4">
              <div class="text-green-600 text-sm font-medium">Venda Atual</div>
              <div class="text-2xl font-bold text-green-800">{@seller_data.sale_value_formatted}</div>
              <div class="text-green-600 text-xs mt-1">{time_ago(@seller_data.timestamp)}</div>
            </div>

            <!-- Meta -->
            <div class="bg-blue-50 border border-blue-200 rounded-xl p-4">
              <div class="text-blue-600 text-sm font-medium">Meta</div>
              <div class="text-2xl font-bold text-blue-800">{@seller_data.objetivo_formatted}</div>
              <div class="text-blue-600 text-xs mt-1">{@seller_stats.goal_percentage}% atingida</div>
            </div>

            <!-- Performance Score -->
            <div class="bg-purple-50 border border-purple-200 rounded-xl p-4">
              <div class="text-purple-600 text-sm font-medium">Score</div>
              <div class="text-2xl font-bold text-purple-800">{@seller_stats.performance_score}</div>
              <div class="text-purple-600 text-xs mt-1">Excelente performance</div>
            </div>

            <!-- Eficiência -->
            <div class="bg-orange-50 border border-orange-200 rounded-xl p-4">
              <div class="text-orange-600 text-sm font-medium">Eficiência</div>
              <div class="text-2xl font-bold text-orange-800">{@seller_stats.efficiency_score}</div>
              <div class="text-orange-600 text-xs mt-1">Vendas/hora</div>
            </div>
          </div>

          <!-- Progress da Meta -->
          <div class="bg-gray-50 rounded-xl p-4 mb-6">
            <div class="flex items-center justify-between mb-2">
              <h3 class="font-medium text-gray-900">Progresso da Meta</h3>
              <span class="text-sm text-gray-600">{@seller_stats.goal_percentage}%</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-4">
              <div
                class={[
                  "h-4 rounded-full transition-all duration-500",
                  if(@seller_stats.goal_percentage >= 100,
                    do: "bg-gradient-to-r from-green-500 to-emerald-500",
                    else: "bg-gradient-to-r from-blue-500 to-purple-500")
                ]}
                style={"width: #{min(@seller_stats.goal_percentage, 100)}%"}
              ></div>
            </div>
            <%= if @seller_stats.is_goal_achieved do %>
              <div class="text-green-600 text-sm mt-1 flex items-center">
                🎉 Meta atingida! Parabéns!
              </div>
            <% else %>
              <div class="text-gray-600 text-sm mt-1">
                Faltam {format_money(@seller_data.objetivo - @seller_data.sale_value)} para atingir a meta
              </div>
            <% end %>
          </div>

          <!-- Gráfico de Histórico -->
          <div class="bg-white border border-gray-200 rounded-xl p-4 mb-6">
            <h3 class="font-medium text-gray-900 mb-4">📊 Histórico de Vendas (últimos 30 dias)</h3>
            <div class="h-32 flex items-end space-x-1">
              <%= for {day_data, index} <- Enum.with_index(@seller_history) do %>
                <div class="flex-1 flex flex-col items-center">
                  <div
                    class={[
                      "w-full rounded-t transition-all duration-300 hover:opacity-80",
                      if(day_data.sales >= day_data.goal, do: "bg-green-400", else: "bg-blue-400")
                    ]}
                    style={"height: #{max(day_data.sales / 15000 * 100, 5)}%"}
                    title="Dia #{31 - day_data.day}: #{format_money(day_data.sales)}"
                  ></div>
                  <%= if rem(index, 5) == 0 do %>
                    <div class="text-xs text-gray-400 mt-1">{Calendar.strftime(day_data.date, "%d/%m")}</div>
                  <% end %>
                </div>
              <% end %>
            </div>
            <div class="flex items-center justify-center space-x-4 mt-3 text-xs">
              <div class="flex items-center space-x-1">
                <div class="w-3 h-3 bg-green-400 rounded"></div>
                <span>Meta atingida</span>
              </div>
              <div class="flex items-center space-x-1">
                <div class="w-3 h-3 bg-blue-400 rounded"></div>
                <span>Abaixo da meta</span>
              </div>
            </div>
          </div>

          <!-- Conquistas -->
          <div class="bg-white border border-gray-200 rounded-xl p-4">
            <h3 class="font-medium text-gray-900 mb-4">🏆 Conquistas</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              <%= for achievement <- @achievements do %>
                <div class={[
                  "p-3 rounded-lg border-2 transition-all",
                  if(achievement.earned,
                    do: "bg-green-50 border-green-200",
                    else: "bg-gray-50 border-gray-200 opacity-50")
                ]}>
                  <div class="flex items-center space-x-2 mb-1">
                    <span class="text-lg">{achievement.icon}</span>
                    <span class={[
                      "font-medium text-sm",
                      if(achievement.earned, do: "text-green-800", else: "text-gray-500")
                    ]}>
                      {achievement.title}
                    </span>
                  </div>
                  <div class={[
                    "text-xs",
                    if(achievement.earned, do: "text-green-600", else: "text-gray-400")
                  ]}>
                    {achievement.description}
                  </div>
                  <%= if achievement.earned and achievement.date do %>
                    <div class="text-xs text-green-500 mt-1">
                      🗓️ {achievement.date}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="border-t border-gray-200 bg-gray-50 p-4">
          <div class="flex items-center justify-between">
            <div class="text-sm text-gray-600">
              🔄 Dados atualizados em tempo real
            </div>
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
    """
  end
end
