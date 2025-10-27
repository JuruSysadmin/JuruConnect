defmodule AppWeb.DashboardResumoLive do
  @moduledoc """
  LiveView principal para o dashboard resumo de vendas.

  Agora funciona como um orquestrador que renderiza os LiveViews separados:
  - MonthlyMetricsLive: Métricas mensais
  - DailyMetricsLive: Métricas diárias
  - ScheduleLive: Agendamento de entregas
  - StoresPerformanceLive: Performance das lojas
  - NotificationsLive: Sistema de notificações
  """

  use AppWeb, :live_view

  import AppWeb.DashboardDailyMetrics
  import AppWeb.DashboardState

  alias App.Dashboard.Orchestrator

  # Constantes
  @animation_duration_ms 2_000
  @orchestrator_timeout_ms 5_000

  @impl true
  @spec mount(map, map, Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:devolucao")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    end

    socket
    |> assign_loading_state()
    |> assign(%{
      previous_sale_value: 0.0,
      animate_sale: false,
      previous_devolution_value: 0.0,
      animate_devolution: false,
      previous_profit_value: 0.0,
      animate_profit: nil,
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
      ticket_medio_diario: "R$ 0,00",
      ticket_medio_mensal: "R$ 0,00"
    })
    |> fetch_and_assign_data_safe()
    |> then(&{:ok, &1})
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:dashboard_updated, data}, socket) do
    now = get_brazil_timestamp()
    data = convert_keys_to_atoms(data)

    updated_socket = socket
    |> assign_daily_data(data, now)
    |> assign(%{
      api_status: :ok,
      last_update: now,
      loading: false,
      api_error: nil
    })

    updated_socket
    |> push_event("update-gauge", %{value: updated_socket.assigns.percentual_num})
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:devolucao_aumentou, %{devolution: val, diff: diff, sellerName: seller}}, socket) do
    msg = "Atenção: Nova devolução registrada para #{seller}! Valor: R$ #{AppWeb.DashboardUtils.format_money(val)} (aumento de R$ #{AppWeb.DashboardUtils.format_money(diff)})"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:devolucao_aumentou, %{anterior: anterior, atual: atual}}, socket) do
    msg = "Atenção: Houve uma nova devolução registrada. Valor total de devoluções do dia: #{AppWeb.DashboardUtils.format_money(atual)} (anterior: #{AppWeb.DashboardUtils.format_money(anterior)})"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info(:clear_sale_animation, socket) do
    {:noreply, assign(socket, animate_sale: false)}
  end

  @impl true
  def handle_info(:clear_devolution_animation, socket) do
    {:noreply, assign(socket, animate_devolution: false)}
  end

  @impl true
  def handle_info(:clear_profit_animation, socket) do
    {:noreply, assign(socket, animate_profit: nil)}
  end

  @spec assign_loading_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_loading_state(socket), do:
    assign(socket, %{loading: true, api_status: :loading, api_error: nil, last_update: nil})

  @spec fetch_and_assign_data_safe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp fetch_and_assign_data_safe(socket) do
    now = get_brazil_timestamp()
    handle_data_response(Orchestrator.get_data(timeout: @orchestrator_timeout_ms), socket, now)
  end

  defp handle_data_response({:ok, data}, socket, now) do
    socket
    |> assign_daily_data(convert_keys_to_atoms(data), now)
    |> assign(%{
      api_status: :ok,
      last_update: now,
      loading: false,
      api_error: nil
    })
  end

  defp handle_data_response({:loading, nil}, socket, _now) do
    assign(socket, %{api_status: :loading, loading: true, api_error: nil, last_update: nil})
  end

  defp handle_data_response({:error, reason}, socket, now) do
    assign_error_data(socket, reason, now)
    |> assign(%{api_status: :error, loading: false, last_update: now})
  end

  defp handle_data_response({:timeout, reason}, socket, now) do
    assign_error_data(socket, "Timeout: #{reason}", now)
    |> assign(%{api_status: :timeout, loading: false, last_update: now})
  end

  defp handle_data_response(_, socket, now) do
    assign_error_data(socket, "Resposta inesperada do servidor", now)
    |> assign(%{api_status: :error, loading: false, last_update: now})
  end

  @spec assign_daily_data(Phoenix.LiveView.Socket.t(), map, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_daily_data(socket, data, now) do
    percentual = AppWeb.DashboardUtils.calculate_percentual_number(data)
    current_sale_value = Map.get(data, :sale, 0.0)
    previous_sale_value = Map.get(socket.assigns, :previous_sale_value, 0.0)
    current_devolution_value = Map.get(data, :devolution, 0.0)
    previous_devolution_value = Map.get(socket.assigns, :previous_devolution_value, 0.0)
    current_profit_value = Map.get(data, :profit, 0.0)
    previous_profit_value = Map.get(socket.assigns, :previous_profit_value, 0.0)

    # Detecta animações
    animate_sale = detect_animations(current_sale_value, previous_sale_value)
    animate_devolution = detect_animations(current_devolution_value, previous_devolution_value)
    animate_profit = detect_profit_animation(current_profit_value, previous_profit_value)

    daily_data = create_daily_metrics_data(data)

    assigns = Map.merge(daily_data, %{
      realizado_hoje_percent: percentual,
      realizado_hoje_formatted: AppWeb.DashboardUtils.format_percent(percentual),
      last_update: now,
      api_status: :ok,
      loading: false,
      api_error: nil,
      previous_sale_value: current_sale_value,
      animate_sale: animate_sale,
      previous_devolution_value: current_devolution_value,
      animate_devolution: animate_devolution,
      previous_profit_value: current_profit_value,
      animate_profit: animate_profit
    })

    socket = assign(socket, assigns)

    # Gerencia animações
    manage_animations(socket, animate_sale, animate_devolution, animate_profit)

    socket
  end

  @spec assign_error_data(Phoenix.LiveView.Socket.t(), any, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_error_data(socket, reason, now) do
    previous_values = %{
      previous_sale_value: Map.get(socket.assigns, :previous_sale_value, 0.0),
      previous_devolution_value: Map.get(socket.assigns, :previous_devolution_value, 0.0),
      previous_profit_value: Map.get(socket.assigns, :previous_profit_value, 0.0)
    }

    error_data = create_error_state_data(previous_values)

    assign(socket, Map.merge(error_data, %{
      api_status: :error,
      api_error: reason,
      loading: false,
      last_update: now
    }))
  end

  defp manage_animations(_socket, animate_sale, animate_devolution, animate_profit) do
    if animate_sale do
      Process.send_after(self(), :clear_sale_animation, @animation_duration_ms)
    end

    if animate_devolution do
      Process.send_after(self(), :clear_devolution_animation, @animation_duration_ms)
    end

    if animate_profit do
      Process.send_after(self(), :clear_profit_animation, @animation_duration_ms)
    end
  end

  @impl true
  @spec render(map) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <!-- Flash de erro -->
    <%= if @flash[:error] do %>
      <div
        id="dashboard-flash-error"
        phx-hook="AutoHideFlash"
        class="fixed top-4 left-1/2 transform -translate-x-1/2 z-50 w-full max-w-xl px-4"
        role="alert"
        aria-live="assertive"
      >
        <div class="alert alert-error animate-fade-in backdrop-blur-sm">
          <svg class="w-6 h-6 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          <div class="flex-1">
            <p class="font-semibold text-sm leading-relaxed"><%= @flash[:error] %></p>
          </div>
        </div>
              </div>
    <% end %>

    <div id="dashboard-main" class="min-h-screen bg-gradient-to-br from-base-200 via-base-100 to-base-200" phx-hook="GoalCelebration">
      <!-- Sistema de Notificações -->
      <%= live_render(@socket, AppWeb.NotificationsLive, id: :notifications) %>

      <!-- Header com Logo -->
      <div class="sticky top-0 z-40 bg-base-100/70 backdrop-blur-xl border-b border-base-300/50 shadow-lg">
        <div class="max-w-[1920px] mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <div class="flex items-center justify-between">
            <!-- Logo -->
            <div class="flex items-center space-x-3">
              <img src={~p"/assets/logo2.svg"} alt="Logo Jurunense" class="h-16 sm:h-20 w-auto" />
                  </div>

            <!-- Status da API e última atualização -->
            <div class="flex items-center space-x-3">
              <%= if @api_status == :ok do %>
                <div class="flex items-center space-x-2 text-xs sm:text-sm text-base-content">
                  <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
                  <span class="hidden sm:inline">Online</span>
                </div>
              <% end %>

              <%= if @last_update do %>
                <div class="text-xs text-base-content/70 hidden md:block">
                  Atualizado: <%= Calendar.strftime(@last_update, "%H:%M:%S") %>
              </div>
            <% end %>
          </div>
              </div>
              </div>
            </div>

      <!-- Layout principal - Responsivo com max-width -->
      <div class="max-w-[1920px] mx-auto px-3 sm:px-4 md:px-6 lg:px-8 py-4 sm:py-5 md:py-6 space-y-4 sm:space-y-5 md:space-y-6">

        <!-- Cards de Métricas em Linha -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-5 md:gap-6 lg:items-stretch">

          <!-- Coluna esquerda: Métricas Mensais -->
          <div class="w-full">
            <%= live_render(@socket, AppWeb.MonthlyMetricsLive, id: :monthly_metrics) %>
              </div>

          <!-- Coluna direita: Cards de métricas DIÁRIAS -->
          <div class="w-full">
            <.daily_metrics
              objetivo={@objetivo}
              sale={@sale}
              devolution={@devolution}
              profit={@profit}
              nfs={@invoices_count}
              ticket_medio_diario={@ticket_medio_diario}
              realizado_hoje_formatted={@realizado_hoje_formatted}
              animate_sale={@animate_sale}
              animate_devolution={@animate_devolution}
              animate_profit={@animate_profit}
            />
              </div>
            </div>

        <!-- Agendamento de Entregas -->
        <div class="w-full">
          <%= live_render(@socket, AppWeb.ScheduleLive, id: :schedule) %>
              </div>

        <!-- Performance das Lojas -->
        <div class="w-full">
          <%= live_render(@socket, AppWeb.StoresPerformanceLive, id: :stores_performance) %>
              </div>
            </div>

      <!-- Mensagem de erro se API estiver offline -->
      <%= if @api_status == :error and @api_error do %>
        <div class="fixed bottom-4 right-4 left-4 sm:left-auto max-w-md z-50" role="alert">
          <div class="alert alert-error shadow-2xl backdrop-blur-sm">
            <svg class="w-6 h-6 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
            <div class="flex-1">
              <h3 class="text-sm font-semibold">Erro de Conexão</h3>
              <p class="text-sm">
                {@api_error}
              </p>
                  </div>
            <button
              type="button"
              phx-click={JS.remove_class("animate-fade-in", to: "#dashboard-error")}
              class="btn btn-sm btn-circle"
              aria-label="Fechar"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
            </button>
                  </div>
                </div>
              <% end %>

      <!-- Footer com informações úteis -->
      <footer class="mt-8 border-t border-base-300/50 bg-base-100/60 backdrop-blur-xl">
        <div class="max-w-[1920px] mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex flex-col sm:flex-row items-center justify-between text-xs text-base-content/70 space-y-2 sm:space-y-0">
            <p>© 2024 Jurunense Home Center - Dashboard em tempo real</p>
            <div class="flex items-center space-x-4">
              <span class="flex items-center space-x-1">
                <div class={[
                  "w-2 h-2 rounded-full",
                  case @api_status do
                    :ok -> "bg-success animate-pulse"
                    :loading -> "bg-warning animate-pulse"
                    :error -> "bg-error"
                    :timeout -> "bg-warning"
                    _ -> "bg-base-300"
                  end
                ]}></div>
                <span>
                  <%= case @api_status do
                    :ok -> "Sistema operacional"
                    :loading -> "Carregando dados..."
                    :error -> "Erro de conexão"
                    :timeout -> "Tempo esgotado"
                    _ -> "Status desconhecido"
                  end %>
                </span>
              </span>
              </div>
          </div>
        </div>
      </footer>
    </div>
    """
  end
end
