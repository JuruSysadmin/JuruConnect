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

    end

    socket =
      socket
      |> assign_loading_state()
      |> assign(
        notifications: [],
        show_celebration: false


      )
      |> fetch_and_assign_data_safe()

    {:ok, socket}
  end



  @impl true
  def handle_info({:dashboard_updated, data}, socket) do
    data_with_atom_keys = convert_keys_to_atoms(data)

    socket =
      assign_success_data(socket, data_with_atom_keys)
      |> assign(
        api_status: :ok,
        last_update: DateTime.utc_now(),
        loading: false,
        api_error: nil
      )

    # Atualiza o gauge se estava em loading
    socket =
      if socket.assigns[:loading] == true do
        socket
      else
        socket
      end

    socket =
      socket
      |> push_event("update-gauge", %{
        value: socket.assigns.percentual_num
      })
      |> push_event("update-gauge-monthly", %{
        value: socket.assigns.percentual_sale
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
  def handle_info({:goal_achieved_real, celebration_data}, socket) do
    # Handler para celebrações REAIS baseadas em dados da API
    celebration_id = celebration_data.celebration_id

    new_notification = %{
      id: celebration_id,
      store_name: get_celebration_store_name(celebration_data),
      achieved: get_celebration_achieved(celebration_data),
      target: get_celebration_target(celebration_data),
      percentage: celebration_data.percentage,
      timestamp: celebration_data.timestamp,
      celebration_id: celebration_id,
      type: celebration_data.type,
      level: celebration_data.level,
      message: get_celebration_message(celebration_data)
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
      |> push_event("goal-achieved-real", %{
        type: celebration_data.type,
        level: celebration_data.level,
        message: new_notification.message,
        store_name: new_notification.store_name,
        achieved: AppWeb.DashboardUtils.format_money(new_notification.achieved),
        celebration_id: celebration_id,
        timestamp: DateTime.to_unix(celebration_data.timestamp, :millisecond),
        sound: Map.get(celebration_data.data, :sound, "goal_achieved.mp3")
      })

    # Duração baseada no nível da celebração
    duration = get_celebration_duration(celebration_data.level)
    Process.send_after(self(), {:hide_specific_notification, celebration_id}, duration)

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
    valor_base = Enum.random(30_000..80_000)
    meta_base = valor_base - Enum.random(5_000..15_000)
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





  defp assign_loading_state(socket) do
    assign(socket,
      loading: true,
      api_status: :loading,
      api_error: nil,
      last_update: nil
    )
  end

  defp fetch_and_assign_data_safe(socket) do
    case DashboardDataServer.get_data(timeout: 5_000) do
      {:ok, data} ->
        # Dados disponíveis - processa imediatamente
        data_with_atom_keys = convert_keys_to_atoms(data)

        socket =
          assign_success_data(socket, data_with_atom_keys)
          |> assign(
            api_status: :ok,
            last_update: DateTime.utc_now(),
            loading: false,
            api_error: nil
          )

        socket

      {:loading, nil} ->
        # Ainda carregando - mantém estado de loading e aguarda PubSub

        assign(socket,
          api_status: :loading,
          loading: true,
          api_error: nil,
          last_update: nil
        )

      {:error, reason} ->
        # Erro na busca - exibe estado de erro

        assign_error_data(socket, reason)
        |> assign(
          api_status: :error,
          loading: false,
          last_update: DateTime.utc_now()
        )

      {:timeout, reason} ->
        # Timeout - trata como erro mas com mensagem específica

        assign_error_data(socket, "Timeout: #{reason}")
        |> assign(
          api_status: :timeout,
          loading: false,
          last_update: DateTime.utc_now()
        )

      _unexpected ->
        # Caso inesperado - fallback

        assign_error_data(socket, "Resposta inesperada do servidor")
        |> assign(
          api_status: :error,
          loading: false,
          last_update: DateTime.utc_now()
        )
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

    # Dados mensais
    sale_mensal_num = Map.get(data, :sale_mensal, 0.0)
    objetivo_mensal_num = Map.get(data, :objetivo_mensal, 0.0)
    devolution_mensal_num = Map.get(data, :devolution_mensal, 0.0)

    assigns = [
      # Dados DIÁRIOS
      sale: format_money(sale_num),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(Map.get(data, :devolution, 0.0)),
      objetivo: format_money(objetivo_num),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: percentual_num,
      realizado_hoje_percent: realizado_hoje_percent,
      realizado_hoje_formatted: format_percent(realizado_hoje_percent),
      nfs: Map.get(data, :nfs, 0) |> trunc(),
      sale_num: sale_num,
      objetivo_num: objetivo_num,

      # Dados MENSAIS
      sale_mensal: format_money(sale_mensal_num),
      objetivo_mensal: format_money(objetivo_mensal_num),
      devolution_mensal: format_money(devolution_mensal_num),
      nfs_mensal: Map.get(data, :nfs_mensal, 0) |> trunc(),
      percentual_sale: percentual_sale,
      sale_mensal_num: sale_mensal_num,
      objetivo_mensal_num: objetivo_mensal_num,
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
      # Dados DIÁRIOS
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "0,00%",
      percentual: "0,00%",
      percentual_num: 0,
      realizado_hoje_percent: 0,
      realizado_hoje_formatted: "0,00%",
      nfs: 0,
      sale_num: 0.0,
      objetivo_num: 0.0,

      # Dados MENSAIS
      sale_mensal: "R$ 0,00",
      objetivo_mensal: "R$ 0,00",
      devolution_mensal: "R$ 0,00",
      nfs_mensal: 0,
      percentual_sale: 0,
      sale_mensal_num: 0.0,
      objetivo_mensal_num: 0.0,
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



  # Funções auxiliares para celebrações reais
  defp get_celebration_store_name(celebration_data) do
    case celebration_data.type do
      :top_seller ->
        Map.get(celebration_data.data, :store, "Loja Desconhecida")

      _ ->
        Map.get(celebration_data.data, :store_name, "Sistema")
    end
  end

  defp get_celebration_achieved(celebration_data) do
    Map.get(celebration_data.data, :achieved, 0.0)
  end

  defp get_celebration_target(celebration_data) do
    Map.get(celebration_data.data, :target, 0.0)
  end

  defp get_celebration_message(celebration_data) do
    base_message = Map.get(celebration_data.data, :message, "Meta Atingida!")

    case celebration_data.type do
      :top_seller ->
        seller_name = Map.get(celebration_data.data, :seller_name, "Vendedor")
        "#{base_message} - #{seller_name}"

      :exceptional_individual_sale ->
        seller_name = Map.get(celebration_data.data, :seller_name, "Vendedor")
        "#{base_message} - #{seller_name}"

      _ ->
        base_message
    end
  end

  defp get_celebration_duration(level) do
    case level do
      # 15 segundos
      :legendary -> 15_000
      # 12 segundos
      :epic -> 12_000
      # 10 segundos
      :major -> 10_000
      # 8 segundos
      :standard -> 8_000
      # 5 segundos
      :minor -> 5_000
      # padrão
      _ -> 8_000
    end
  end

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

      /* Responsividade customizada */
      @media (max-width: 640px) {
        .mobile-hide { display: none !important; }
        .mobile-stack { flex-direction: column !important; }
        .mobile-full { width: 100% !important; }
        .mobile-text-xs { font-size: 0.65rem !important; }
        .mobile-p-2 { padding: 0.5rem !important; }
      }

      @media (max-width: 768px) {
        .tablet-hide { display: none !important; }
        .tablet-stack { flex-direction: column !important; }
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
      <div class="fixed top-4 right-2 sm:right-4 z-40 space-y-2 w-80 sm:w-auto">
        <!-- Contador de Celebrações Ativas -->
        <%= if length(@notifications) > 0 do %>
          <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-2 rounded-full shadow-lg text-center animate-pulse">
            <span class="text-xs sm:text-sm font-medium">
              {length(@notifications)} Celebrações Globais Ativas
            </span>
          </div>
        <% end %>

    <!-- Notificações Individuais -->
        <%= for {notification, index} <- Enum.with_index(@notifications) do %>
          <div
            class="bg-gradient-to-r from-green-500 to-emerald-600 text-white p-3 sm:p-4 rounded-lg shadow-2xl max-w-sm bounce-in transform hover:scale-105 transition-all duration-300"
            style={"animation-delay: #{index * 0.1}s;"}
            id={"notification-#{notification.celebration_id}"}
          >
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0 relative">
                <!-- Ícone removido -->
                <div class="absolute -top-1 -right-1 w-3 h-3 bg-yellow-400 rounded-full animate-ping">
                </div>
              </div>
              <div class="flex-1">
                <h4 class="text-sm sm:text-base font-medium animate-bounce">
                  Meta #{index + 1} Atingida!
                  <span class="text-xs bg-white bg-opacity-20 px-2 py-1 rounded-full ml-2">
                    GLOBAL
                  </span>
                </h4>
                <p class="text-xs sm:text-sm opacity-90 font-medium">{notification.store_name}</p>
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
                                                                                   else: "0,0"}%)
                </p>
                <p class="text-xs opacity-60 mt-1 mobile-hide">
                  ID: #{notification.celebration_id}
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>

    <!-- Header com status da API -->
      <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between w-full px-3 sm:px-6 py-3 sm:py-4 mb-3 sm:mb-4 space-y-2 sm:space-y-0">
        <div>
          <h1 class="text-lg sm:text-xl font-medium text-gray-900">JURUNENSE HOME CENTER</h1>
          <p class="text-xs text-gray-600 mt-1 mobile-hide"></p>
        </div>
        <div class="flex flex-col sm:flex-row items-start sm:items-center space-y-2 sm:space-y-0 sm:space-x-4 w-full sm:w-auto">
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
            <span class="text-xs text-gray-400 mobile-hide">
              Atualizado: {Calendar.strftime(@last_update, "%H:%M:%S")}
            </span>
          <% end %>

    <!-- Botões de Teste -->
          <div class="flex flex-col sm:flex-row space-y-1 sm:space-y-0 sm:space-x-2 w-full sm:w-auto">
            <button
              phx-click="test_goal_achieved"
              class="relative px-2 sm:px-3 py-2 bg-gradient-to-r from-green-500 to-emerald-600 hover:from-green-600 hover:to-emerald-700 text-white rounded-lg shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 text-xs font-medium animate-pulse hover:animate-none border border-green-400 hover:border-green-300 w-full sm:w-auto"
              title="Clique para testar a animação de meta atingida"
            >
              <span class="flex items-center justify-center space-x-1">
                <span class="text-sm mobile-hide"></span>
                <span class="text-center">Testar Celebração</span>
              </span>
            </button>
          </div>
        </div>
      </div>

    <!-- Layout principal - Responsivo -->
      <div class="flex flex-col xl:flex-row gap-4 sm:gap-6 md:gap-8 px-3 sm:px-6 md:px-8">
        <!-- Coluna esquerda: Cards e Gráficos -->
        <div class="flex-1 space-y-4 sm:space-y-5 md:space-y-6 w-full xl:w-4/12">
          <!-- Cards de métricas DIÁRIAS - Grid responsivo balanceado -->
          <div class="grid grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-3 xl:grid-cols-3 gap-3 sm:gap-4 md:gap-5">
            <.card title="Meta Diária" value={@objetivo} subtitle=""></.card>

            <.card title="Vendas Diárias" value={@sale} subtitle=""></.card>

            <.card title="Devoluções Diárias" value={@devolution} subtitle="">
            </.card>

            <.card title="Margem Diária" value={@profit} subtitle=""></.card>

            <.card title="NFs Diárias" value={@nfs} subtitle=""></.card>

            <.card
              title="% Realizado Hoje"
              value={@realizado_hoje_formatted}
              subtitle=""
            >
            </.card>
          </div>

    <!-- Seção de Metas em Tempo Real -->
          <div class="grid grid-cols-1 gap-4 sm:gap-5">
            <!-- Card - Realizado: até ontem -->
            <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-4 sm:p-5 md:p-6 transition-all duration-300 hover:shadow-xl">
              <div class="text-center mb-4 sm:mb-5">
                <h2 class="text-base sm:text-lg font-medium text-gray-900 mb-1">Realizado: Mensal</h2>
              </div>

              <div class="flex flex-col sm:flex-row items-center justify-center sm:justify-between gap-5 sm:gap-6">
                <!-- Gráfico Circular -->
                <div class="flex justify-center">
                  <%= if @loading do %>
                    <div class="w-24 h-24 sm:w-32 sm:h-32 flex items-center justify-center">
                      <div class="animate-spin rounded-full h-6 w-6 sm:h-8 sm:w-8 border-b-2 border-blue-500">
                      </div>
                    </div>
                  <% else %>
                    <div class="relative">
                      <canvas
                        id="gauge-chart-2"
                        phx-hook="GaugeChartMonthly"
                        phx-update="ignore"
                        data-value={min(@percentual_sale, 100)}
                        class="w-24 h-24 sm:w-32 sm:h-32"
                      >
                      </canvas>
                      <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                        <span class="text-lg sm:text-xl font-medium text-gray-800">
                          {format_percent(@percentual_sale)}
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>

    <!-- Dados Absolutos MENSAIS -->
                <div class="flex flex-col space-y-3 text-center sm:text-left">
                  <div class="bg-gray-50 rounded-lg p-3 sm:p-4">
                    <div class="text-xs text-gray-600 mb-1">Meta Mensal</div>
                    <div class="font-mono text-sm sm:text-base font-medium text-gray-900">
                      {@objetivo_mensal}
                    </div>
                  </div>

                  <div class="bg-blue-50 rounded-lg p-3 sm:p-4">
                    <div class="text-xs text-gray-600 mb-1">Vendas Mensais</div>
                    <div class="font-mono text-sm sm:text-base font-medium text-blue-700">
                      {@sale_mensal}
                    </div>
                  </div>

                  <div class="bg-red-50 rounded-lg p-3 sm:p-4">
                    <div class="text-xs text-gray-600 mb-1">Devoluções Mensais</div>
                    <div class="font-mono text-sm sm:text-base font-medium text-red-700">
                      {@devolution_mensal}
                    </div>
                  </div>

                  <%= if @sale_mensal_num > 0 and @objetivo_mensal_num > 0 do %>
                    <div class="bg-green-50 rounded-lg p-3 sm:p-4">
                      <div class="text-xs text-gray-600 mb-1">Falta Atingir (Mensal)</div>
                      <div class="font-mono text-sm sm:text-base font-medium text-green-700">
                        {format_money(@objetivo_mensal_num - @sale_mensal_num)}
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>


        </div>

    <!-- Coluna direita: Tabela de Performance das Lojas - Responsiva (MAIOR) -->
        <div class="w-full xl:w-8/12 order-first xl:order-last">
          <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-4 sm:p-6">
            <!-- Header igual ao feed de vendas -->
            <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-4 space-y-2 sm:space-y-0">
              <div>
                <h2 class="text-sm sm:text-base font-medium text-gray-900 mb-1">
                  Performance das Lojas
                </h2>
                <p class="text-xs text-gray-500">
                  {length(@lojas_data)} lojas ativas • Atualização em tempo real
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <div class="w-2 h-2 rounded-full bg-green-500"></div>
                <span class="text-xs text-gray-600">AO VIVO</span>
              </div>
            </div>

    <!-- Tabela Responsiva -->
            <div class="overflow-x-auto">
              <!-- Versão Desktop/Tablet da Tabela -->
              <table class="w-full animate-fade-in-scale text-sm hidden sm:table">
                <thead class="bg-gray-100">
                  <tr>
                    <th class="text-left py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">
                      Loja
                    </th>
                    <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">
                      Meta Dia
                    </th>
                    <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">
                      Meta Hora
                    </th>
                    <th class="text-center py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">
                      NFs
                    </th>
                    <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">
                      Venda Dia
                    </th>
                    <th class="text-center py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">
                      % Hora
                    </th>
                    <th class="text-center py-3 px-4 text-sm font-medium text-gray-600">
                      % Dia
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= if @loading do %>
                    <%= for _i <- 1..5 do %>
                      <tr class="animate-pulse">
                        <td class="py-4 px-4 border-r border-gray-200">
                          <div class="flex items-center space-x-3">
                            <div class="w-4 h-4 bg-gray-300 rounded-full shimmer-effect"></div>
                            <div class="h-4 bg-gray-300 rounded w-32 shimmer-effect"></div>
                          </div>
                        </td>
                        <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                          <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                          <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-4 border-r border-gray-200">
                          <div class="h-4 bg-gray-300 rounded-full w-10 mx-auto shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-4 border-r border-gray-200">
                          <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                          <div class="h-4 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
                        </td>
                        <td class="py-4 px-4">
                          <div class="h-4 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
                        </td>
                      </tr>
                    <% end %>
                  <% else %>
                    <%= for {loja, index} <- Enum.with_index(@lojas_data) do %>
                      <tr class={[
                        if(rem(index, 2) == 0, do: "bg-white", else: "bg-gray-50"),
                        "hover:bg-gray-100 transition-colors duration-200"
                      ]}>
                        <td class="py-4 px-4 border-r border-gray-200">
                          <div class="flex items-center space-x-3">
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
                              <div class="font-medium text-gray-900 text-sm">
                                {loja.nome}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="text-right py-4 px-4 tablet-hide border-r border-gray-200">
                          <span class="font-mono text-gray-800 text-sm">
                            {format_money(loja.meta_dia)}
                          </span>
                        </td>
                        <td class="text-right py-4 px-4 tablet-hide border-r border-gray-200">
                          <span class="font-mono text-gray-800 text-sm">
                            {format_money(loja.meta_hora)}
                          </span>
                        </td>
                        <td class="text-center py-4 px-4 border-r border-gray-200">
                          <span class="text-sm text-gray-800 font-medium">
                            {loja.qtde_nfs}
                          </span>
                        </td>
                        <td class="text-right py-4 px-4 border-r border-gray-200">
                          <span class={[
                            "font-mono text-sm font-medium",
                            if(loja.venda_dia >= loja.meta_dia,
                              do: "text-green-700",
                              else: "text-gray-800"
                            )
                          ]}>
                            {format_money(loja.venda_dia)}
                          </span>
                        </td>
                        <td class="text-center py-4 px-4 tablet-hide border-r border-gray-200">
                          <span class="text-sm text-gray-800 font-medium">
                            {if is_number(loja.perc_hora),
                              do:
                                (loja.perc_hora * 1.0)
                                |> :erlang.float_to_binary(decimals: 1)
                                |> String.replace(".", ","),
                              else: "0,0"}%
                          </span>
                        </td>
                        <td class="text-center py-4 px-4">
                          <span class={[
                            "text-sm font-medium",
                            cond do
                              is_number(loja.perc_dia) and loja.perc_dia >= 100 -> "text-green-700"
                              is_number(loja.perc_dia) and loja.perc_dia >= 80 -> "text-yellow-700"
                              true -> "text-red-700"
                            end
                          ]}>
                            {if is_number(loja.perc_dia),
                              do:
                                (loja.perc_dia * 1.0)
                                |> :erlang.float_to_binary(decimals: 1)
                                |> String.replace(".", ","),
                              else: "0,0"}%
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>

    <!-- Versão Mobile da Tabela (Cards) -->
              <div class="block sm:hidden space-y-2">
                <%= if @loading do %>
                  <%= for _i <- 1..3 do %>
                    <div class="bg-gray-50 p-3 rounded-lg animate-pulse">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-2">
                          <div class="w-3 h-3 bg-gray-300 rounded-full shimmer-effect"></div>
                          <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
                        </div>
                        <div class="h-4 bg-gray-300 rounded w-16 shimmer-effect"></div>
                      </div>
                    </div>
                  <% end %>
                <% else %>
                  <%= for loja <- @lojas_data do %>
                    <div class="bg-gray-50 p-3 rounded-lg">
                      <div class="flex items-center justify-between">
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
                            <div class="font-medium text-gray-900 text-sm">{loja.nome}</div>
                            <div class="text-xs text-gray-500">NFs: {loja.qtde_nfs}</div>
                          </div>
                        </div>
                        <div class="text-right">
                          <div class="font-mono text-sm text-gray-900">
                            {format_money(loja.venda_dia)}
                          </div>
                          <div class="text-xs text-gray-500">
                            {if is_number(loja.perc_dia),
                              do:
                                (loja.perc_dia * 1.0)
                                |> :erlang.float_to_binary(decimals: 1)
                                |> String.replace(".", ","),
                              else: "0,0"}%
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

    <!-- Mensagem de erro se API estiver offline -->
      <%= if @api_status == :error and @api_error do %>
        <div class="mt-6 sm:mt-8 p-4 bg-red-50 border border-red-200 rounded-lg max-w-md mx-3 sm:mx-8">
          <div class="flex items-center">
            <!-- Ícone removido -->
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
