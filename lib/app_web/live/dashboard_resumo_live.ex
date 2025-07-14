defmodule AppWeb.DashboardResumoLive do
  @moduledoc """
  LiveView para o dashboard resumo de vendas.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardComponents
  import AppWeb.DashboardUtils
  import AppWeb.DashboardNotificationPanel
  import AppWeb.DashboardDailyMetrics
  import AppWeb.DashboardStoresTable
  import AppWeb.DashboardConfetti

  alias App.DashboardDataServer
  alias AppWeb.DashboardCelebrationUtils

  import Timex

  @impl true
  @spec mount(map, map, Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
    end

    today = Date.utc_today()
    hourly_sales_map =
      App.Sales.list_hourly_sales_history(today)
      |> Map.new(fn %{hour: h, total_sales: s} -> {h, s} end)

    sales_per_hour = for hour <- 0..23, do: Map.get(hourly_sales_map, hour, 0.0)

    socket
    |> assign_loading_state()
    |> assign(%{
      notifications: [],
      show_celebration: false,
      sales_per_hour: sales_per_hour
    })
    |> fetch_and_assign_data_safe()
    |> then(&assign_template_values(&1))
    |> then(&{:ok, &1})
  end

  @spec assign_template_values(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_template_values(socket) do
    assigns = socket.assigns
    socket
    |> assign(%{
      percentual_sale_display: format_percent(assigns.percentual_sale),
      percentual_sale_capped: min(assigns.percentual_sale, 100),
      goal_remaining_display: format_money(assigns.monthly_goal_value - assigns.monthly_sale_value),
      show_goal_remaining: assigns.monthly_sale_value > 0 and assigns.monthly_goal_value > 0
    })
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:dashboard_updated, data}, socket) do
    now = DateTime.utc_now() |> Timex.Timezone.convert("America/Sao_Paulo")
    data = convert_keys_to_atoms(data)

    socket
    |> assign_success_data(data, now)
    |> assign(%{
      api_status: :ok,
      last_update: now,
      loading: false,
      api_error: nil
    })
    |> push_event("update-gauge", %{value: socket.assigns.percentual_num})
    |> push_event("update-gauge-monthly", %{value: socket.assigns.percentual_sale})
    |> push_event("update-fusion-gauge", %{value: socket.assigns.percentual_sale})
    |> then(&{:noreply, &1})
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
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
      notifications: [notification | socket.assigns.notifications] |> Enum.take(10),
      show_celebration: true
    })
    |> push_event("goal-achieved-multiple", %{
      store_name: data.store_name,
      achieved: formatted_achieved,
      celebration_id: celebration_id,
      timestamp: unix_timestamp
    })
    |> then(fn socket ->
      Process.send_after(self(), {:hide_specific_notification, celebration_id}, 8000)
      {:noreply, socket}
    end)
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:goal_achieved_real, data}, socket) do
    celebration_id = data.celebration_id

    notification = %{
      id: celebration_id,
      store_name: DashboardCelebrationUtils.store_name(data),
      achieved: DashboardCelebrationUtils.achieved(data),
      target: DashboardCelebrationUtils.target(data),
      percentage: data.percentage,
      timestamp: data.timestamp,
      celebration_id: celebration_id,
      type: data.type,
      level: data.level,
      message: DashboardCelebrationUtils.message(data)
    }

    formatted_achieved = format_money(notification.achieved)
    unix_timestamp = DateTime.to_unix(data.timestamp, :millisecond)
    sound = Map.get(data.data, :sound, "goal_achieved.mp3")
    duration = DashboardCelebrationUtils.duration(data.level)

    socket
    |> assign(%{
      notifications: [notification | socket.assigns.notifications] |> Enum.take(10),
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
      Process.send_after(self(), {:hide_specific_notification, celebration_id}, duration)
      {:noreply, socket}
    end)
  end

  @impl true
  @spec handle_info(:hide_celebration, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:hide_celebration, socket), do:
    {:noreply, assign(socket, show_celebration: false)}

  @impl true
  @spec handle_info({:hide_specific_notification, any}, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:hide_specific_notification, id}, socket) do
    updated = Enum.reject(socket.assigns.notifications, &(&1.celebration_id == id))
    show = updated != []

    {:noreply, assign(socket, notifications: updated, show_celebration: show)}
  end

  @spec assign_loading_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_loading_state(socket), do:
    assign(socket, %{loading: true, api_status: :loading, api_error: nil, last_update: nil})

  @spec fetch_and_assign_data_safe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp fetch_and_assign_data_safe(socket) do
    now = DateTime.utc_now() |> Timex.Timezone.convert("America/Sao_Paulo")

    case DashboardDataServer.get_data(timeout: 5_000) do
      {:ok, data} ->
        socket
        |> assign_success_data(convert_keys_to_atoms(data), now)
        |> assign(%{
          api_status: :ok,
          last_update: now,
          loading: false,
          api_error: nil
        })
        |> push_event("update-fusion-gauge", %{value: Map.get(data, :percentualSale, 0.0)})

      {:loading, nil} ->
        assign(socket, %{api_status: :loading, loading: true, api_error: nil, last_update: nil})

      {:error, reason} ->
        assign_error_data(socket, reason, now)
        |> assign(%{api_status: :error, loading: false, last_update: now})

      {:timeout, reason} ->
        assign_error_data(socket, "Timeout: #{reason}", now)
        |> assign(%{api_status: :timeout, loading: false, last_update: now})

      _ ->
        assign_error_data(socket, "Resposta inesperada do servidor", now)
        |> assign(%{api_status: :error, loading: false, last_update: now})
    end
  end

  @spec convert_keys_to_atoms(map) :: map
  defp convert_keys_to_atoms(map) when is_map(map),
    do: (for {k, v} <- map, into: %{}, do: {String.to_atom(k), v})

  @spec convert_keys_to_atoms(any) :: map
  defp convert_keys_to_atoms(_), do: %{}

  @spec assign_success_data(Phoenix.LiveView.Socket.t(), map, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_success_data(socket, data, now) do
    percentual = calculate_percentual_number(data)
    assigns = %{
      sale: format_money(Map.get(data, :sale, 0.0)),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(Map.get(data, :devolution, 0.0)),
      objetivo: format_money(Map.get(data, :objetivo, 0.0)),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: percentual,
      realizado_hoje_percent: percentual,
      realizado_hoje_formatted: format_percent(percentual),
      invoices_count: Map.get(data, :nfs, 0) |> trunc(),
      sale_value: Map.get(data, :sale, 0.0),
      goal_value: Map.get(data, :objetivo, 0.0),
      sale_mensal: format_money(Map.get(data, :sale_mensal, 0.0)),
      objetivo_mensal: format_money(Map.get(data, :objetivo_mensal, 0.0)),
      devolution_mensal: format_money(Map.get(data, :devolution_mensal, 0.0)),
      monthly_invoices_count: Map.get(data, :nfs_mensal, 0) |> trunc(),
      percentual_sale: Map.get(data, :percentualSale, 0.0),
      monthly_sale_value: Map.get(data, :sale_mensal, 0.0),
      monthly_goal_value: Map.get(data, :objetivo_mensal, 0.0),
      lojas_data: get_companies_data(data),
      last_update: now,
      api_status: :ok,
      loading: false,
      api_error: nil
    }

    assign(socket, assigns)
  end

  @spec assign_error_data(Phoenix.LiveView.Socket.t(), any, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_error_data(socket, reason, now) do
    assign(socket, %{
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "0,00%",
      percentual: "0,00%",
      percentual_num: 0,
      realizado_hoje_percent: 0,
      realizado_hoje_formatted: "0,00%",
      invoices_count: 0,
      sale_value: 0.0,
      goal_value: 0.0,
      sale_mensal: "R$ 0,00",
      objetivo_mensal: "R$ 0,00",
      devolution_mensal: "R$ 0,00",
      monthly_invoices_count: 0,
      percentual_sale: 0,
      monthly_sale_value: 0.0,
      monthly_goal_value: 0.0,
      lojas_data: [],
      api_status: :error,
      api_error: reason,
      loading: false,
      last_update: now
    })
  end

  @spec get_companies_data(map) :: list
  defp get_companies_data(%{companies: companies}) when is_list(companies), do: companies
  @spec get_companies_data(any) :: list
  defp get_companies_data(_), do: []

  @impl true
  @spec render(map) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="dashboard-main" class="min-h-screen bg-white" phx-hook="GoalCelebration">
      <!-- Confetti/Celebration Effect -->
      <.confetti notifications={@notifications} show_celebration={@show_celebration} />

      <!-- Painel de Notificações -->
      <.notification_panel notifications={@notifications} show_celebration={@show_celebration} />

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
              <div class={["w-3 h-3 rounded-full", if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")]}> </div>
              <span class="text-sm text-gray-600">
                <%= case @api_status do %>
                  <% :ok -> %> API Online
                  <% :loading -> %> Conectando...
                  <% _ -> %> API Offline
                <% end %>
              </span>
            </div>
          <% end %>

          <%= if @last_update do %>
            <span class="text-xs text-gray-400 mobile-hide">
              Atualizado: {Calendar.strftime(@last_update, "%H:%M:%S")}
            </span>
          <% end %>
        </div>
      </div>

      <!-- Layout principal - Responsivo -->
      <div class="flex flex-col xl:flex-row gap-4 sm:gap-6 md:gap-8 px-3 sm:px-6 md:px-8">
        <!-- Coluna esquerda: Cards e Gráficos -->
        <div class="flex-1 space-y-4 sm:space-y-5 md:space-y-6 w-full xl:w-4/12">
          <!-- Cards de métricas DIÁRIAS -->
          <.daily_metrics objetivo={@objetivo} sale={@sale} devolution={@devolution} profit={@profit} nfs={@invoices_count} realizado_hoje_formatted={@realizado_hoje_formatted} />

          <!-- Remover o card do gauge Realizado Mensal (com ponteiro) -->
          <!-- Seção de Metas em Tempo Real permanece inline -->
          <div class="grid grid-cols-1 gap-4 sm:gap-5">
            <!-- Card - Realizado: até ontem -->
            <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-4 sm:p-5 md:p-6 transition-all duration-300 hover:shadow-xl">
              <div class="text-center mb-4 sm:mb-5">
                <h2 class="text-base sm:text-lg font-bold text-blue-700 mb-1 flex items-center justify-center gap-2">
                  <svg xmlns='http://www.w3.org/2000/svg' class='h-5 w-5 text-blue-500' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M13 16h-1v-4h-1m4 0h-1v-4h-1m4 0h-1v-4h-1' /></svg>
                  Realizado até ontem
                </h2>
              </div>

              <div class="flex flex-col items-center justify-center gap-6">
                <!-- Gráfico Circular -->
                <div class="flex justify-center w-full">
                  <%= if @loading do %>
                    <div class="w-32 h-32 flex items-center justify-center">
                      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
                    </div>
                  <% else %>
                    <div class="relative w-32 h-32 sm:w-40 sm:h-40">
                      <canvas
                        id="gauge-chart-2"
                        phx-hook="GaugeChartMonthly"
                        phx-update="ignore"
                        data-value={@percentual_sale_capped}
                        class="w-32 h-32 sm:w-40 sm:h-40"
                      >
                      </canvas>
                      <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                        <span class="text-2xl sm:text-3xl font-bold text-blue-700 drop-shadow">
                          {@percentual_sale_display}
                        </span>
                        <span class="text-xs text-gray-500 mt-1">do objetivo mensal</span>
                      </div>
                    </div>
                  <% end %>
                </div>

                <!-- Cards horizontais -->
                <div class="flex flex-col sm:flex-row gap-3 w-full justify-center items-center mt-2">
                  <div class="flex-1 min-w-[120px] bg-gray-50 rounded-lg p-3 flex flex-col items-center shadow-sm border border-gray-100">
                    <div class="flex items-center gap-1 text-xs text-gray-600 mb-1">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 text-gray-400' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' /></svg>
                      Meta Mensal
                    </div>
                    <div class="font-mono text-base font-semibold text-gray-900">{@objetivo_mensal}</div>
                  </div>
                  <div class="flex-1 min-w-[120px] bg-blue-50 rounded-lg p-3 flex flex-col items-center shadow-sm border border-blue-100">
                    <div class="flex items-center gap-1 text-xs text-blue-700 mb-1">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 text-blue-400' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M3 17l6-6 4 4 8-8' /></svg>
                      Vendas Mensais
                    </div>
                    <div class="font-mono text-base font-semibold text-blue-700">{@sale_mensal}</div>
                  </div>
                  <div class="flex-1 min-w-[120px] bg-red-50 rounded-lg p-3 flex flex-col items-center shadow-sm border border-red-100">
                    <div class="flex items-center gap-1 text-xs text-red-700 mb-1">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 text-red-400' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M6 18L18 6M6 6l12 12' /></svg>
                      Devoluções
                    </div>
                    <div class="font-mono text-base font-semibold text-red-700">{@devolution_mensal}</div>
                  </div>
                  <%= if @show_goal_remaining do %>
                    <div class="flex-1 min-w-[120px] bg-green-50 rounded-lg p-3 flex flex-col items-center shadow-sm border border-green-100">
                      <div class="flex items-center gap-1 text-xs text-green-700 mb-1">
                        <svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 text-green-400' fill='none' viewBox='0 0 24 24' stroke='currentColor'><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' /></svg>
                        Falta Atingir
                      </div>
                      <div class="font-mono text-base font-semibold text-green-700">{@goal_remaining_display}</div>
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
            <.stores_table lojas_data={@lojas_data} loading={@loading} />
          </div>
        </div>
      </div>

      <!-- Mensagem de erro se API estiver offline -->
      <%= if @api_status == :error and @api_error do %>
        <div class="mt-6 sm:mt-8 p-4 bg-red-50 border border-red-200 rounded-lg max-w-md mx-3 sm:mx-8">
          <div class="flex items-center">
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
