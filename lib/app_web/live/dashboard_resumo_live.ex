defmodule AppWeb.DashboardResumoLive do
  @moduledoc """
  LiveView para o dashboard resumo de vendas.
  """

  use AppWeb, :live_view
  import AppWeb.DashboardComponents
  import AppWeb.DashboardUtils
  alias App.DashboardDataServer

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
      Phoenix.PubSub.subscribe(App.PubSub, "sales:feed")
    end

    socket =
      socket
      |> assign_loading_state()
      |> assign(
        notifications: [],
        show_celebration: false,
        sales_feed: []
      )
      |> fetch_and_assign_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:dashboard_updated, data}, socket) do
    data_with_atom_keys = convert_keys_to_atoms(data)
    socket = assign_success_data(socket, data_with_atom_keys)

    socket =
      push_event(socket, "update-gauge", %{
        value: socket.assigns.percentual_num
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:daily_goal_achieved, goal_data}, socket) do
    celebration_id = Map.get(goal_data, :celebration_id, System.unique_integer([:positive]))

    new_notification = %{
      id: celebration_id,
      store_name: goal_data.store_name,
      achieved: goal_data.achieved,
      target: goal_data.target,
      percentage: goal_data.percentage,
      timestamp: goal_data.timestamp,
      celebration_id: celebration_id
    }

    updated_notifications =
      [new_notification | socket.assigns.notifications]
      |> Enum.take(10)

    socket =
      socket
      |> assign(
        notifications: updated_notifications,
        show_celebration: true
      )
      |> push_event("goal-achieved-multiple", %{
        store_name: goal_data.store_name,
        achieved: AppWeb.DashboardUtils.format_money(goal_data.achieved),
        celebration_id: celebration_id,
        timestamp: DateTime.to_unix(goal_data.timestamp, :millisecond)
      })

    Process.send_after(self(), {:hide_specific_notification, celebration_id}, 8000)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:hide_celebration, socket) do
    {:noreply, assign(socket, show_celebration: false)}
  end

  @impl true
  def handle_info({:hide_specific_notification, celebration_id}, socket) do
    updated_notifications =
      socket.assigns.notifications
      |> Enum.reject(&(&1.celebration_id == celebration_id))

    show_celebration = length(updated_notifications) > 0

    {:noreply,
     assign(socket,
       notifications: updated_notifications,
       show_celebration: show_celebration
     )}
  end

  @impl true
  def handle_info({:new_sale, sale_data}, socket) do
    sale_value = normalize_decimal(sale_data.sale_value)
    objetivo = normalize_decimal(sale_data.objetivo)

    new_sale = %{
      id: sale_data.id,
      seller_name: sale_data.seller_name,
      store: sale_data.store,
      sale_value: sale_value,
      sale_value_formatted: AppWeb.DashboardUtils.format_money(sale_value),
      objetivo: objetivo,
      objetivo_formatted: AppWeb.DashboardUtils.format_money(objetivo),
      timestamp: sale_data.timestamp,
      timestamp_formatted: Calendar.strftime(sale_data.timestamp, "%H:%M:%S"),
      type: sale_data.type
    }

    updated_feed =
      [new_sale | socket.assigns.sales_feed]
      |> Enum.sort_by(& &1.sale_value, :desc)
      |> Enum.take(15)

    {:noreply, assign(socket, sales_feed: updated_feed)}
  end

  @impl true
  def handle_event("test_goal_achieved", _params, socket) do
    celebration_id = System.unique_integer([:positive])

    lojas_teste = [
      "Loja Centro - TESTE",
      "Loja Norte - TESTE",
      "Loja Sul - TESTE",
      "Loja Shopping - TESTE",
      "Loja Matriz - TESTE"
    ]

    loja_random = Enum.random(lojas_teste)
    valor_base = Enum.random(30000..80000)
    meta_base = valor_base - Enum.random(5000..15000)
    percentual = (valor_base / meta_base * 100) |> Float.round(1)

    goal_data = %{
      store_name: loja_random,
      achieved: valor_base * 1.0,
      target: meta_base * 1.0,
      percentage: percentual,
      timestamp: DateTime.utc_now(),
      celebration_id: celebration_id
    }

    Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:daily_goal_achieved, goal_data})

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_feed", _params, socket) do
    socket = load_sales_feed(socket)
    socket = put_flash(socket, :info, "Feed atualizado com sucesso!")
    {:noreply, socket}
  end

  @impl true
  def handle_event("simulate_sale", _params, socket) do
    sellers = [
      %{name: "João Carlos", initials: "JC", color: "blue"},
      %{name: "Maria Silva", initials: "MS", color: "green"},
      %{name: "Roberto Alves", initials: "RA", color: "purple"},
      %{name: "Ana Ferreira", initials: "AF", color: "yellow"},
      %{name: "Pedro Costa", initials: "PC", color: "indigo"},
      %{name: "Carla Santos", initials: "CS", color: "pink"},
      %{name: "Rafael Oliveira", initials: "RO", color: "red"},
      %{name: "Lucia Martins", initials: "LM", color: "orange"}
    ]

    products = [
      %{
        name: "Furadeira Bosch",
        category: "Ferramentas Elétricas",
        brand: "Bosch",
        status: "Em Alta"
      },
      %{
        name: "Tinta Suvinil",
        category: "Tintas e Vernizes",
        brand: "Suvinil",
        status: "Crescendo"
      },
      %{
        name: "Kit Banheiro Deca",
        category: "Materiais Hidráulicos",
        brand: "Deca",
        status: "Destaque"
      },
      %{
        name: "Cimento Votoran",
        category: "Materiais de Construção",
        brand: "Votoran",
        status: "Estável"
      },
      %{
        name: "Piso Portinari",
        category: "Pisos e Revestimentos",
        brand: "Portinari",
        status: "Top Vendas"
      },
      %{name: "Parafuso Phillips", category: "Ferragens", brand: "Gerdau", status: "Forte"},
      %{name: "Luminária LED", category: "Iluminação", brand: "Philips", status: "Brilhante"},
      %{
        name: "Torneira Docol",
        category: "Materiais Hidráulicos",
        brand: "Docol",
        status: "Fluindo"
      }
    ]

    seller = Enum.random(sellers)
    product = Enum.random(products)

    amount_ranges = [
      {100..500, 0.3},
      {500..2000, 0.4},
      {2000..5000, 0.2},
      {5000..15000, 0.1}
    ]

    {min..max, _} = Enum.random(amount_ranges)
    base_amount = Enum.random(min..max) * 1.0
    random_cents = :rand.uniform() * 100
    amount = base_amount + random_cents

    sale_value = normalize_decimal(amount)

    base_objetivo = Enum.random(1000..8000) * 1.0
    random_objetivo = :rand.uniform() * 500
    objetivo = normalize_decimal(base_objetivo + random_objetivo)

    sale_data = %{
      id: System.unique_integer([:positive]),
      seller_name: seller.name,
      store: "Loja #{Enum.random(1..5)}",
      sale_value: sale_value,
      objetivo: objetivo,
      timestamp: DateTime.utc_now(),
      type: :sale_supervisor
    }

    Phoenix.PubSub.broadcast(App.PubSub, "sales:feed", {:new_sale, sale_data})

    {:noreply, socket}
  end

  defp assign_loading_state(socket) do
    assign(socket,
      loading: true,
      api_status: :loading,
      api_error: nil,
      last_update: nil
    )
  end

  defp fetch_and_assign_data(socket) do
    case DashboardDataServer.get_data() do
      %{api_status: :ok, data: data} = state when not is_nil(data) ->
        data_with_atom_keys = convert_keys_to_atoms(data)

        socket =
          assign_success_data(socket, data_with_atom_keys)
          |> assign(
            api_status: state.api_status,
            last_update: state.last_update,
            loading: false
          )

        load_sales_feed(socket)

      %{api_status: status, api_error: error} = state ->
        assign_error_data(socket, error)
        |> assign(
          api_status: status,
          last_update: state.last_update,
          loading: false
        )

      _ ->
        assign_error_data(socket, "Dados não disponíveis")
        |> assign(
          api_status: :error,
          loading: false
        )
    end
  end

  defp load_sales_feed(socket) do
    case App.Dashboard.get_sales_feed(15) do
      {:ok, sales_feed} ->
        assign(socket, sales_feed: sales_feed)

      {:error, _reason} ->
        assign(socket, sales_feed: [])
    end
  end

  defp convert_keys_to_atoms(data) when is_map(data) do
    for {k, v} <- data, into: %{}, do: {String.to_atom(k), v}
  end

  defp convert_keys_to_atoms(_), do: %{}

  defp assign_success_data(socket, data) do
    percentual_num = calculate_percentual_number(data)
    sale_num = Map.get(data, :sale, 0.0)
    objetivo_num = Map.get(data, :objetivo, 0.0)
    percentual_sale = Map.get(data, :percentualSale, 0.0)
    realizado_hoje_percent = percentual_num

    assigns = [
      sale: format_money(sale_num),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(Map.get(data, :devolution, 0.0)),
      objetivo: format_money(objetivo_num),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: percentual_num,
      percentual_sale: percentual_sale,
      realizado_hoje_percent: realizado_hoje_percent,
      realizado_hoje_formatted: format_percent(realizado_hoje_percent),
      nfs: Map.get(data, :nfs, 0) |> trunc(),
      sale_num: sale_num,
      objetivo_num: objetivo_num,
      lojas_data: get_companies_data(data),
      last_update: DateTime.utc_now(),
      api_status: :ok,
      loading: false,
      api_error: nil
    ]

    assign(socket, assigns)
  end

  defp assign_error_data(socket, reason) do
    assign(socket,
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "0,00%",
      percentual: "0,00%",
      percentual_num: 0,
      percentual_sale: 0,
      realizado_hoje_percent: 0,
      realizado_hoje_formatted: "0,00%",
      nfs: 0,
      lojas_data: get_companies_data(%{}),
      api_status: :error,
      api_error: reason,
      loading: false,
      last_update: socket.assigns[:last_update]
    )
  end

  defp calculate_percentual_number(data) do
    case Map.get(data, :percentual, 0.0) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) -> parse_percent_to_number(value)
      _ -> 0.0
    end
  end

  defp get_companies_data(data) do
    case Map.get(data, :companies) do
      companies when is_list(companies) -> companies
      _ -> []
    end
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> Calendar.strftime(datetime, "%d/%m")
    end
  end

  defp normalize_decimal(value) when is_float(value), do: Float.round(value, 2)
  defp normalize_decimal(value) when is_integer(value), do: Float.round(value * 1.0, 2)

  defp normalize_decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> Float.round(num, 2)
      :error -> 0.0
    end
  end

  defp normalize_decimal(nil), do: 0.0
  defp normalize_decimal(_), do: 0.0

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      @keyframes slideInUp {
        from {
          opacity: 0;
          transform: translate3d(0, 100%, 0);
        }
        to {
          opacity: 1;
          transform: translate3d(0, 0, 0);
        }
      }

      @keyframes fadeInScale {
        from {
          opacity: 0;
          transform: scale(0.9);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }

      @keyframes shimmer {
        0% {
          background-position: -200px 0;
        }
        100% {
          background-position: calc(200px + 100%) 0;
        }
      }

      .animate-slide-in-up {
        animation: slideInUp 0.6s ease-out;
      }

      .animate-fade-in-scale {
        animation: fadeInScale 0.4s ease-out;
      }

      .shimmer-effect {
        background: linear-gradient(90deg, transparent, rgba(255,255,255,0.4), transparent);
        background-size: 200px 100%;
        animation: shimmer 2s infinite;
      }

      .table-row-stagger {
        animation-delay: calc(var(--row-index) * 0.1s);
      }

      @keyframes confetti {
        0% { transform: translateY(-100vh) rotate(0deg); opacity: 1; }
        100% { transform: translateY(100vh) rotate(720deg); opacity: 0; }
      }

      .confetti {
        animation: confetti 3s linear infinite;
      }

      @keyframes bounceIn {
        0% { transform: scale(0.3); opacity: 0; }
        50% { transform: scale(1.05); }
        70% { transform: scale(0.9); }
        100% { transform: scale(1); opacity: 1; }
      }

      .bounce-in {
        animation: bounceIn 0.6s ease-out;
      }
    </style>
    <div id="dashboard-main" class="min-h-screen bg-white" phx-hook="GoalCelebration">
      <!-- Notificações de Meta Atingida com Confetti em Tempo Real -->
      <%= if @show_celebration do %>
        <div class="fixed inset-0 z-50 pointer-events-none">
          <!-- Confetti Effect - Múltiplas camadas para cada clique -->
          <%= for {_notification, index} <- Enum.with_index(@notifications) do %>
            <!-- Layer 1 - Confetti principal -->
            <div
              class="absolute top-0 left-[10%] w-3 h-3 bg-yellow-400 confetti"
              style={"animation-delay: #{index * 0.1}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[20%] w-2 h-2 bg-green-400 confetti"
              style={"animation-delay: #{index * 0.1 + 0.2}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[30%] w-3 h-3 bg-blue-400 confetti"
              style={"animation-delay: #{index * 0.1 + 0.4}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[40%] w-2 h-2 bg-red-400 confetti"
              style={"animation-delay: #{index * 0.1 + 0.6}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[50%] w-3 h-3 bg-purple-400 confetti"
              style={"animation-delay: #{index * 0.1 + 0.8}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[60%] w-2 h-2 bg-pink-400 confetti"
              style={"animation-delay: #{index * 0.1 + 1.0}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[70%] w-3 h-3 bg-indigo-400 confetti"
              style={"animation-delay: #{index * 0.1 + 1.2}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[80%] w-2 h-2 bg-orange-400 confetti"
              style={"animation-delay: #{index * 0.1 + 1.4}s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[90%] w-3 h-3 bg-emerald-400 confetti"
              style={"animation-delay: #{index * 0.1 + 1.6}s;"}
            >
            </div>
            
    <!-- Layer 2 - Confetti secundário -->
            <div
              class="absolute top-0 left-[15%] w-1 h-1 bg-yellow-300 confetti"
              style={"animation-delay: #{index * 0.1 + 0.3}s; animation-duration: 3.5s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[25%] w-1 h-1 bg-green-300 confetti"
              style={"animation-delay: #{index * 0.1 + 0.5}s; animation-duration: 4s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[35%] w-1 h-1 bg-blue-300 confetti"
              style={"animation-delay: #{index * 0.1 + 0.7}s; animation-duration: 3s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[45%] w-1 h-1 bg-red-300 confetti"
              style={"animation-delay: #{index * 0.1 + 0.9}s; animation-duration: 3.5s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[55%] w-1 h-1 bg-purple-300 confetti"
              style={"animation-delay: #{index * 0.1 + 1.1}s; animation-duration: 4s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[65%] w-1 h-1 bg-pink-300 confetti"
              style={"animation-delay: #{index * 0.1 + 1.3}s; animation-duration: 3s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[75%] w-1 h-1 bg-indigo-300 confetti"
              style={"animation-delay: #{index * 0.1 + 1.5}s; animation-duration: 3.5s;"}
            >
            </div>
            <div
              class="absolute top-0 left-[85%] w-1 h-1 bg-orange-300 confetti"
              style={"animation-delay: #{index * 0.1 + 1.7}s; animation-duration: 4s;"}
            >
            </div>
          <% end %>
        </div>
      <% end %>
      
    <!-- Painel de Notificações com Contador -->
      <div class="fixed top-4 right-4 z-40 space-y-2">
        <!-- Contador de Celebrações Ativas -->
        <%= if length(@notifications) > 0 do %>
          <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-2 rounded-full shadow-lg text-center animate-pulse">
            <span class="text-sm font-bold">{length(@notifications)} Celebrações Globais Ativas</span>
          </div>
        <% end %>
        
    <!-- Notificações Individuais -->
        <%= for {notification, index} <- Enum.with_index(@notifications) do %>
          <div
            class="bg-gradient-to-r from-green-500 to-emerald-600 text-white p-4 rounded-lg shadow-2xl max-w-sm bounce-in transform hover:scale-105 transition-all duration-300"
            style={"animation-delay: #{index * 0.1}s;"}
            id={"notification-#{notification.celebration_id}"}
          >
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0 relative">
                <svg
                  class="w-8 h-8 text-white animate-spin"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <div class="absolute -top-1 -right-1 w-3 h-3 bg-yellow-400 rounded-full animate-ping">
                </div>
              </div>
              <div class="flex-1">
                <h4 class="font-bold text-lg animate-bounce">
                  Meta #{index + 1} Atingida!
                  <span class="text-xs bg-white bg-opacity-20 px-2 py-1 rounded-full ml-2">
                    GLOBAL
                  </span>
                </h4>
                <p class="text-sm opacity-90 font-semibold">{notification.store_name}</p>
                <p class="text-xs opacity-75">
                  {AppWeb.DashboardUtils.format_money(notification.achieved)} ({if is_number(
                                                                                     notification.percentage
                                                                                   ),
                                                                                   do:
                                                                                     :erlang.float_to_binary(
                                                                                       notification.percentage *
                                                                                         1.0,
                                                                                       decimals: 1
                                                                                     ),
                                                                                   else: "0.0"}%)
                </p>
                <p class="text-xs opacity-60 mt-1">
                  ID: #{notification.celebration_id}
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Header com status da API -->
      <div class="flex items-center justify-between w-full px-6 py-4 mb-4">
        <div>
          <h1 class="text-2xl font-extrabold text-gray-900 tracking-tight">JURUNENSE HOME CENTER</h1>
          <p class="text-xs text-gray-600 mt-1"></p>
        </div>
        <div class="flex items-center space-x-4">
          <%= if @loading do %>
            <div class="flex items-center space-x-2">
              <div class="w-3 h-3 rounded-full bg-blue-500 animate-pulse"></div>
              <span class="text-sm text-gray-600">Carregando...</span>
            </div>
          <% else %>
            <div class="flex items-center space-x-2">
              <div class={[
                "w-3 h-3 rounded-full",
                if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")
              ]}>
              </div>
              <span class="text-sm text-gray-600">
                <%= case @api_status do %>
                  <% :ok -> %>
                    API Online
                  <% :loading -> %>
                    Conectando...
                  <% _ -> %>
                    API Offline
                <% end %>
              </span>
            </div>
          <% end %>

          <%= if @last_update do %>
            <span class="text-xs text-gray-400">
              Atualizado: {Calendar.strftime(@last_update, "%H:%M:%S")}
            </span>
          <% end %>
          
    <!-- Botões de Teste -->
          <div class="flex space-x-2">
            <button
              phx-click="test_goal_achieved"
              class="relative px-3 py-2 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-600 hover:to-emerald-700 text-white rounded-lg shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 text-xs font-bold animate-pulse hover:animate-none border border-green-400 hover:border-green-300"
              title="Clique para testar a animação de meta atingida"
            >
              <span class="flex items-center space-x-1">
                <span class="text-sm"></span>
                <span>Testar Celebração</span>
              </span>
            </button>

            <button
              phx-click="simulate_sale"
              class="relative px-3 py-2 bg-gradient-to-r from-blue-500 to-cyan-600 hover:from-blue-600 hover:to-cyan-700 text-white rounded-lg shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 text-xs font-bold animate-pulse hover:animate-none border border-blue-400 hover:border-blue-300"
              title="Clique para simular uma nova venda (ranking automático)"
            >
              <span class="flex items-center space-x-1">
                <span class="text-sm"></span>
                <span>Simular Venda (Ranking)</span>
              </span>
            </button>
          </div>
        </div>
      </div>
      
    <!-- Layout principal dividido -->
      <div class="flex gap-4 px-6">
        <!-- Coluna esquerda: Cards e Gráficos -->
        <div class="flex-1 space-y-4">
          <!-- Cards de métricas -->
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-3 gap-4">
            <.card title="Meta diaria" value={@objetivo} subtitle="" icon_bg="bg-yellow-50"></.card>

            <.card title="Faturamento Liquido" value={@sale} subtitle="" icon_bg="bg-green-50">
            </.card>

            <.card title="Devoluções" value={@devolution} subtitle="" icon_bg="bg-red-50"></.card>

            <.card title="Margem" value={@profit} subtitle="" icon_bg="bg-green-100"></.card>

            <.card title="Notas fiscais" value={@nfs} subtitle="" icon_bg="bg-purple-50"></.card>

            <.card
              title="Realizado Hoje"
              value={@realizado_hoje_formatted}
              subtitle=""
              icon_bg="bg-blue-50"
            >
            </.card>
          </div>
          
    <!-- Seção de Metas em Tempo Real -->
          <div class="grid grid-cols-1 gap-4">
            <!-- Card - Realizado até ontem -->
            <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-4 transition-all duration-300 hover:shadow-xl">
              <div class="text-center mb-3">
                <h2 class="text-lg font-bold text-gray-900 mb-1">Realizado Mensal</h2>
              </div>

              <div class="flex justify-center">
                <%= if @loading do %>
                  <div class="w-32 h-32 flex items-center justify-center">
                    <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
                  </div>
                <% else %>
                  <div class="relative">
                    <canvas
                      id="gauge-chart-2"
                      phx-hook="GaugeChart"
                      phx-update="ignore"
                      data-value={min(@percentual_sale, 100)}
                      class="w-32 h-32"
                    >
                    </canvas>
                    <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                      <span class="text-2xl font-bold text-gray-800">
                        {format_percent(@percentual_sale)}
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Feed de Vendas em Tempo Real - Estilo Twitter -->
          <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-4 min-h-[550px]">
            <div class="flex items-center justify-between mb-4">
              <div>
                <h2 class="text-lg font-bold text-gray-900 mb-1">Feed Vendas</h2>
                <p class="text-xs text-gray-500">
                  Ordenado por valor de venda (maior para menor) • Precisão: 2 casas decimais
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <button
                  phx-click="refresh_feed"
                  class="px-3 py-1 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded text-xs font-medium transition-colors border"
                  title="Atualizar feed"
                >
                  Atualizar
                </button>
                <div class="w-2 h-2 rounded-full bg-green-500"></div>
                <span class="text-xs text-gray-600">AO VIVO</span>
              </div>
            </div>
            
    <!-- Feed Container - Estilo Twitter -->
            <div class="h-[450px] overflow-y-auto space-y-3 pr-1" id="sales-feed">
              <%= if Enum.empty?(@sales_feed) do %>
                <!-- Estado vazio -->
                <div class="text-center py-8">
                  <div class="w-12 h-12 mx-auto bg-gray-100 rounded-full flex items-center justify-center mb-3">
                    <svg
                      class="w-6 h-6 text-gray-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"
                      />
                    </svg>
                  </div>
                  <p class="text-gray-500 text-sm font-medium mb-1">Feed vazio</p>
                </div>
              <% else %>
                <!-- Cards de dados do Supervisor -->
                <%= for {sale, index} <- Enum.with_index(@sales_feed) do %>
                  <div
                    class={
                      [
                        "rounded p-3 hover:shadow-sm transition-shadow relative",
                        case index do
                          # 1º lugar - Ouro
                          0 -> "bg-yellow-50 border-2 border-yellow-300"
                          # 2º lugar - Prata
                          1 -> "bg-gray-50 border-2 border-gray-400"
                          # 3º lugar - Bronze
                          2 -> "bg-orange-50 border-2 border-orange-300"
                          _ -> "bg-white border border-gray-200"
                        end
                      ]
                    }
                    id={"sale-#{sale.id}"}
                  >
                    <!-- Posição no ranking -->
                    <div class={[
                      "absolute top-2 right-2 text-xs px-2 py-1 rounded",
                      case index do
                        0 -> "bg-yellow-200 text-yellow-800 font-bold"
                        1 -> "bg-gray-200 text-gray-800 font-bold"
                        2 -> "bg-orange-200 text-orange-800 font-bold"
                        _ -> "bg-gray-100 text-gray-600"
                      end
                    ]}>
                      #{index + 1}
                    </div>
                    
    <!-- Cabeçalho -->
                    <div class="flex items-center justify-between mb-2 pr-8">
                      <h4 class="font-medium text-gray-900 text-sm">{sale.seller_name}</h4>
                      <span class="text-xs text-gray-500">{time_ago(sale.timestamp)}</span>
                    </div>
                    
    <!-- Loja -->
                    <div class="text-gray-600 mb-3 text-sm">
                      <span class="font-medium">{sale.store}</span>
                    </div>
                    
    <!-- Dados -->
                    <div class="space-y-2">
                      <%= if sale.objetivo > 0 do %>
                        <div class="flex justify-between text-sm">
                          <span class="text-gray-600">Objetivo:</span>
                          <span class="font-medium text-gray-900">{sale.objetivo_formatted}</span>
                        </div>
                      <% end %>

                      <%= if sale.sale_value > 0 do %>
                        <div class="flex justify-between text-sm">
                          <span class="text-gray-600">Venda:</span>
                          <div class="text-right">
                            <span class="font-medium text-green-600">
                              {sale.sale_value_formatted}
                            </span>
                            <div class="text-xs text-gray-400">
                              ({if is_number(sale.sale_value),
                                do: :erlang.float_to_binary(sale.sale_value * 1.0, decimals: 2),
                                else: "0.00"})
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                    
    <!-- Rodapé -->
                    <div class="mt-3 pt-2 border-t border-gray-100">
                      <div class="flex items-center justify-between text-xs text-gray-400">
                        <span>{sale.timestamp_formatted}</span>
                        <span>Vendaweb</span>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Coluna direita: Tabela de Performance das Lojas -->
        <div class="w-6/12">
          <div class="bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
            <!-- Header da Tabela -->
            <div class="bg-gradient-to-r from-blue-600 to-blue-900 px-4 py-3">
              <h2 class="text-lg font-bold text-white">Performance das Lojas</h2>
            </div>
            
    <!-- Filtros e Controles -->
            <div class="bg-gray-50 px-4 py-2 border-b border-gray-200">
              <div class="flex items-center justify-between">
                <span class="text-xs text-gray-500">
                  {length(@lojas_data)} lojas ativas
                </span>
                <span class="text-xs text-gray-500">Atualização em tempo real</span>
              </div>
            </div>
            
    <!-- Tabela -->
            <div class="overflow-x-auto">
              <table class="w-full animate-fade-in-scale text-sm">
                <thead class="bg-gradient-to-r from-gray-50 to-gray-100">
                  <tr>
                    <th class="text-left py-2 px-3 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      <div class="flex items-center space-x-1">
                        <svg
                          class="w-3 h-3 text-gray-600"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"
                          />
                        </svg>
                        <span>Loja</span>
                      </div>
                    </th>
                    <th class="text-right py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      Meta Dia
                    </th>
                    <th class="text-right py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      Meta Hora
                    </th>
                    <th class="text-center py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      NFs
                    </th>
                    <th class="text-right py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      Venda Dia
                    </th>
                    <th class="text-center py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      % Hora
                    </th>
                    <th class="text-center py-2 px-2 font-bold text-gray-800 uppercase tracking-wider text-xs">
                      % Dia
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= if @loading do %>
                    <%= for _i <- 1..5 do %>
                      <tr class="animate-pulse">
                        <td class="py-4 px-6">
                          <div class="flex items-center space-x-4">
                            <div class="w-4 h-4 bg-gray-300 rounded-full shimmer-effect"></div>
                            <div class="h-4 bg-gray-300 rounded w-48 shimmer-effect"></div>
                          </div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-6 bg-gray-300 rounded-full w-12 mx-auto shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-6 bg-gray-300 rounded-full w-16 mx-auto shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-6">
                          <div class="h-6 bg-gray-300 rounded-full w-16 mx-auto shimmer-effect"></div>
                        </td>
                      </tr>
                    <% end %>
                  <% else %>
                    <%= for {loja, index} <- Enum.with_index(@lojas_data) do %>
                      <tr class={[
                        if(rem(index, 2) == 0, do: "bg-white", else: "bg-gray-50")
                      ]}>
                        <td class="py-2 px-3">
                          <div class="flex items-center space-x-2">
                            <div class={[
                              "w-3 h-3 rounded-full",
                              case loja.status do
                                :atingida_hora -> "bg-green-500"
                                :abaixo_meta -> "bg-red-500"
                                :sem_vendas -> "bg-gray-400"
                                _ -> "bg-yellow-500"
                              end
                            ]}>
                            </div>
                            <div>
                              <div class="font-semibold text-gray-900 text-sm">
                                {loja.nome}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="text-right py-2 px-2">
                          <span class="font-mono text-gray-800 text-xs">
                            {format_money(loja.meta_dia)}
                          </span>
                        </td>
                        <td class="text-right py-2 px-2">
                          <span class="font-mono text-gray-800 text-xs">
                            {format_money(loja.meta_hora)}
                          </span>
                        </td>
                        <td class="text-center py-2 px-2">
                          <span class="text-xs font-medium text-gray-800">
                            {loja.qtde_nfs}
                          </span>
                        </td>
                        <td class="text-right py-2 px-2">
                          <span class={[
                            "font-mono text-xs",
                            if(loja.venda_dia >= loja.meta_dia,
                              do: "text-green-700",
                              else: "text-gray-800"
                            )
                          ]}>
                            {format_money(loja.venda_dia)}
                          </span>
                        </td>
                        <td class="text-center py-2 px-2">
                          <span class="text-xs font-medium text-gray-800">
                            {if is_number(loja.perc_hora),
                              do: :erlang.float_to_binary(loja.perc_hora * 1.0, decimals: 1),
                              else: "0.0"}%
                          </span>
                        </td>
                        <td class="text-center py-2 px-2">
                          <span class="text-xs font-medium text-gray-800">
                            {if is_number(loja.perc_dia),
                              do: :erlang.float_to_binary(loja.perc_dia * 1.0, decimals: 1),
                              else: "0.0"}%
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
                <!-- Footer com totais -->
                <tfoot>
                  <tr class="bg-gradient-to-r from-gray-800 to-gray-900 text-white">
                    <td class="py-2 px-3 font-bold text-sm">
                      <div class="flex items-center space-x-1">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                          />
                        </svg>
                        <span>TOTAL</span>
                      </div>
                    </td>
                    <td class="text-right py-2 px-2 font-bold text-xs font-mono">{@objetivo}</td>
                    <td class="text-right py-2 px-2 font-bold text-xs font-mono">
                      {format_money(434_761.80)}
                    </td>
                    <td class="text-center py-2 px-2">
                      <span class="text-xs font-bold text-white">
                        {@nfs}
                      </span>
                    </td>
                    <td class="text-right py-2 px-2 font-bold text-xs font-mono">{@sale}</td>
                    <td class="text-center py-2 px-2">
                      <span class="text-xs font-bold text-white">
                        108,56%
                      </span>
                    </td>
                    <td class="text-center py-2 px-2">
                      <span class="text-xs font-bold text-white">
                        {@percentual}
                      </span>
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Mensagem de erro se API estiver offline -->
      <%= if @api_status == :error and @api_error do %>
        <div class="mt-8 p-4 bg-red-50 border border-red-200 rounded-lg max-w-md mx-8">
          <div class="flex items-center">
            <svg
              class="w-5 h-5 text-red-500 mr-2"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span class="text-sm text-red-700">
              Erro na API: {@api_error}
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
