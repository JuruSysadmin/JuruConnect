defmodule AppWeb.DashboardResumoLive do
  @moduledoc """
  LiveView para o dashboard resumo de vendas.
  """

  use AppWeb, :live_view

  import AppWeb.DashboardUtils
  import AppWeb.DashboardNotificationPanel
  import AppWeb.DashboardDailyMetrics
  import AppWeb.DashboardStoresTable
  import AppWeb.SupervisorModal
  import AppWeb.DashboardComponents
  import AppWeb.DashboardSchedule

  alias App.Dashboard.Orchestrator
  alias App.Dashboard.SupervisorMonitor

  @impl true
  @spec mount(map, map, Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:devolucao")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:schedule")
    end

    socket
    |> assign_loading_state()
    |> assign(%{
      notifications: [],
      show_celebration: false,
      show_drawer: false,
      supervisor_data: [],
      supervisor_loading: false,
      previous_sale_value: 0.0,
      animate_sale: false,
      previous_devolution_value: 0.0,
      animate_devolution: false,
      previous_profit_value: 0.0,
      animate_profit: nil,
      lojas_data: [],
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
      schedule_data: []
    })
    |> fetch_and_assign_data_safe()
    |> fetch_schedule_data()
    |> then(&assign_template_values(&1))
    |> then(&{:ok, &1})
  end

  @spec assign_template_values(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_template_values(socket) do
    assigns = socket.assigns

    percentual_sale = Map.get(assigns, :percentual_sale, 0.0)
    monthly_sale_value = Map.get(assigns, :monthly_sale_value, 0.0)
    monthly_goal_value = Map.get(assigns, :monthly_goal_value, 0.0)

    socket
    |> assign(%{
      percentual_sale_display: format_percent(percentual_sale),
      percentual_sale_capped: min(percentual_sale, 100),
      goal_remaining_display: format_money(monthly_goal_value - monthly_sale_value),
      show_goal_remaining: monthly_sale_value > 0 and monthly_goal_value > 0
    })
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:dashboard_updated, data}, socket) do
    now = DateTime.utc_now() |> Timex.Timezone.convert("America/Sao_Paulo")
    data = convert_keys_to_atoms(data)

    updated_socket = socket
    |> assign_success_data(data, now)
    |> assign(%{
      api_status: :ok,
      last_update: now,
      loading: false,
      api_error: nil
    })
    |> assign_template_values()

    updated_socket
    |> push_event("update-gauge", %{value: updated_socket.assigns.percentual_num})
    |> push_event("update-gauge-monthly", %{value: updated_socket.assigns.percentual_sale})
    |> push_event("update-fusion-gauge", %{value: updated_socket.assigns.percentual_sale})
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
      store_name: data.data.store_name,
      achieved: data.data.achieved,
      target: data.data.target,
      percentage: data.percentage,
      timestamp: data.timestamp,
      celebration_id: celebration_id,
      type: data.type,
      level: data.level,
      message: data.data.message,
      supervisor_id: Map.get(data.data, :supervisor_id)
    }

    formatted_achieved = format_money(notification.achieved)
    unix_timestamp = DateTime.to_unix(data.timestamp, :millisecond)
    sound = Map.get(data.data, :sound, "goal_achieved.mp3")
    duration = 8000

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

  # Atualiza supervisor_data em tempo real ao receber evento PubSub
  @impl true
  def handle_info({:supervisor_updated, supervisor_data}, socket) do
    {:noreply, assign(socket, supervisor_data: supervisor_data)}
  end

  # Atualiza schedule_data em tempo real ao receber evento PubSub
  @impl true
  def handle_info({:schedule_updated, schedule_data}, socket) do
    schedule_list = if is_list(schedule_data), do: schedule_data, else: [schedule_data]
    {:noreply, assign(socket, schedule_data: schedule_list)}
  end

  @impl true
  def handle_info({:devolucao_aumentou, %{devolution: val, diff: diff, sellerName: seller}}, socket) do
    msg = "Atenção: Nova devolução registrada para #{seller}! Valor: R$ #{format_money(val)} (aumento de R$ #{format_money(diff)})"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl true
  def handle_info({:devolucao_aumentou, %{anterior: anterior, atual: atual}}, socket) do
    msg = "Atenção: Houve uma nova devolução registrada. Valor total de devoluções do dia: #{format_money(atual)} (anterior: #{format_money(anterior)})"
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

  @impl true
  @doc """
  Evento para exibir o modal de supervisor. Realiza subscribe no tópico PubSub do supervisor, busca os dados atuais via API e atribui ao socket. Permite atualização em tempo real via PubSub.
  """
  def handle_event("show_supervisor_drawer", %{"supervisor-id" => id}, socket) do
    topic = "supervisor:#{id}"
    Phoenix.PubSub.subscribe(App.PubSub, topic)

    # Registra no monitor para atualizações em tempo real
    SupervisorMonitor.subscribe_supervisor(id)

    # Mostra loading enquanto busca dados
    socket = assign(socket, %{
      show_drawer: true,
      supervisor_loading: true,
      supervisor_topic: topic,
      supervisor_id: id
    })

    # Busca dados de forma assíncrona
    case fetch_supervisor_data(id) do
      data when is_list(data) ->
        {:noreply, assign(socket, supervisor_data: data, supervisor_loading: false)}
      _ ->
        {:noreply, assign(socket, supervisor_data: [], supervisor_loading: false)}
    end
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    if topic = socket.assigns[:supervisor_topic] do
      Phoenix.PubSub.unsubscribe(App.PubSub, topic)
    end

    # Remove do monitor quando fechar
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

  defp fetch_supervisor_data(id) do
    fetch_supervisor_data_from_api(id)
  end

  defp fetch_supervisor_data_from_api(id) do
    case App.ApiClient.fetch_supervisor_data(id) do
      {:ok, sale_supervisors} -> sale_supervisors
      {:error, _reason} -> []
    end
  end

  @doc false
  defp fetch_schedule_data(socket) do
    case App.ApiClient.fetch_schedule_data() do
      {:ok, data} ->
        schedule_list = if is_list(data), do: data, else: [data]
        assign(socket, schedule_data: schedule_list)
      {:error, _reason} ->
        assign(socket, schedule_data: [])
    end
  end

  @spec assign_loading_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_loading_state(socket), do:
    assign(socket, %{loading: true, api_status: :loading, api_error: nil, last_update: nil})

  @spec fetch_and_assign_data_safe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp fetch_and_assign_data_safe(socket) do
    now = DateTime.utc_now() |> Timex.Timezone.convert("America/Sao_Paulo")
    handle_data_response(Orchestrator.get_data(timeout: 5_000), socket, now)
  end

  defp handle_data_response({:ok, data}, socket, now) do
    socket
    |> assign_success_data(convert_keys_to_atoms(data), now)
    |> assign(%{
      api_status: :ok,
      last_update: now,
      loading: false,
      api_error: nil
    })
    |> push_event("update-fusion-gauge", %{value: Map.get(data, :percentualSale, 0.0)})
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

  @spec convert_keys_to_atoms(map) :: map
  defp convert_keys_to_atoms(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> convert_key_to_atom(k, v) end)
    |> Enum.into(%{})
  end

  @spec convert_keys_to_atoms(any) :: map
  defp convert_keys_to_atoms(_), do: %{}

  defp convert_key_to_atom(k, v) when is_binary(k) do
    {String.to_existing_atom(k), v}
  rescue
    ArgumentError -> {k, v}
  end

  defp convert_key_to_atom(k, v), do: {k, v}

  @spec assign_success_data(Phoenix.LiveView.Socket.t(), map, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_success_data(socket, data, now) do
    percentual = calculate_percentual_number(data)
    current_sale_value = Map.get(data, :sale, 0.0)
    previous_sale_value = Map.get(socket.assigns, :previous_sale_value, 0.0)
    current_devolution_value = Map.get(data, :devolution, 0.0)
    previous_devolution_value = Map.get(socket.assigns, :previous_devolution_value, 0.0)
    current_profit_value = Map.get(data, :profit, 0.0)
    previous_profit_value = Map.get(socket.assigns, :previous_profit_value, 0.0)

    # Detecta se houve aumento nas vendas
    animate_sale = current_sale_value > previous_sale_value and previous_sale_value > 0

    # Detecta se houve aumento nas devoluções
    animate_devolution = current_devolution_value > previous_devolution_value and previous_devolution_value > 0

    # Detecta mudança na margem (profit)
    animate_profit = cond do
      current_profit_value > previous_profit_value and previous_profit_value != 0.0 -> :up
      current_profit_value < previous_profit_value and previous_profit_value != 0.0 -> :down
      true -> nil
    end

    assigns = %{
      sale: format_money(current_sale_value),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(current_devolution_value),
      objetivo: format_money(Map.get(data, :objetivo, 0.0)),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: percentual,
      realizado_hoje_percent: percentual,
      realizado_hoje_formatted: format_percent(percentual),
      invoices_count: Map.get(data, :nfs, 0) |> trunc(),
      sale_value: current_sale_value,
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
      api_error: nil,
      previous_sale_value: current_sale_value,
      animate_sale: animate_sale,
      previous_devolution_value: current_devolution_value,
      animate_devolution: animate_devolution,
      previous_profit_value: current_profit_value,
      animate_profit: animate_profit
    }

    socket = assign(socket, assigns)

    # Se houver animação, envia evento JS e depois desativa após 2 segundos
    if animate_sale do
      Process.send_after(self(), :clear_sale_animation, 2000)
    end

    if animate_devolution do
      Process.send_after(self(), :clear_devolution_animation, 2000)
    end

    if animate_profit do
      Process.send_after(self(), :clear_profit_animation, 2000)
    end

    socket
  end

  @spec assign_error_data(Phoenix.LiveView.Socket.t(), any, DateTime.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_error_data(socket, reason, now) do
    # Mantém o valor anterior de vendas e devoluções para não perder o tracking
    previous_sale_value = Map.get(socket.assigns, :previous_sale_value, 0.0)
    previous_devolution_value = Map.get(socket.assigns, :previous_devolution_value, 0.0)
    previous_profit_value = Map.get(socket.assigns, :previous_profit_value, 0.0)

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
      last_update: now,
      previous_sale_value: previous_sale_value,
      animate_sale: false,
      previous_devolution_value: previous_devolution_value,
      animate_devolution: false,
      previous_profit_value: previous_profit_value,
      animate_profit: nil
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
    <%= if @flash[:error] do %>
      <div id="dashboard-flash-error" phx-hook="AutoHideFlash" class="fixed top-4 left-1/2 transform -translate-x-1/2 z-50 w-full max-w-md px-4" role="alert" aria-live="assertive">
        <div class="bg-red-100 border border-red-300 text-red-800 px-4 py-3 rounded-lg shadow-lg flex items-center space-x-2 animate-fade-in">
          <svg class="w-5 h-5 text-red-500 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 5.636l-1.414-1.414A9 9 0 105.636 18.364l1.414 1.414A9 9 0 1018.364 5.636z" />
          </svg>
          <span class="font-semibold"><%= @flash[:error] %></span>
        </div>
      </div>
    <% end %>
    <div id="dashboard-main" class="min-h-screen bg-white" phx-hook="GoalCelebration">
      <!-- Painel de Notificações -->
      <.notification_panel notifications={@notifications} />

      <!-- Logo apenas -->
      <div class="flex justify-center w-full mb-1">
        <img src={~p"/assets/logo2.svg"} alt="Logo Jurunense" class="dashboard-logo" />
      </div>

      <!-- Agendamento de Entregas -->
      <div class="px-3 sm:px-6 md:px-8 mb-4">
        <.schedule_card schedule_data={@schedule_data} />
      </div>

      <!-- Layout principal - Responsivo -->
      <div class="px-3 sm:px-6 md:px-8 space-y-4 sm:space-y-5 md:space-y-6">
        <!-- Tabela de Performance das Lojas - No Topo -->
        <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-3 sm:p-4 hover:shadow-xl transition-shadow duration-300">
          <!-- Header igual ao feed de vendas -->
          <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-3 space-y-2 sm:space-y-0">
            <div>
              <h2 class="text-sm sm:text-base font-bold text-gray-900 mb-0.5 flex items-center gap-2">
                Performance das Lojas
              </h2>
              <p class="text-xs text-gray-500">
                {length(@lojas_data)} lojas ativas • Atualização em tempo real
              </p>
            </div>
            <div class="flex items-center space-x-2 px-2.5 py-1 bg-green-50 rounded-full border border-green-200" role="status" aria-label="Sistema em tempo real">
              <div class="w-2 h-2 rounded-full bg-green-500 animate-pulse" aria-hidden="true"></div>
              <span class="text-xs text-green-700 font-bold">AO VIVO</span>
            </div>
          </div>

          <!-- Tabela Responsiva -->
          <.stores_table lojas_data={@lojas_data} loading={@loading} />
        </div>

        <!-- Cards de Métricas em Linha -->
        <div class="flex flex-col lg:flex-row gap-4 sm:gap-5 md:gap-6 lg:items-stretch">
          <!-- Coluna esquerda: Cards de métricas DIÁRIAS -->
          <div class="flex-1 w-full lg:w-7/12 flex">
            <.daily_metrics objetivo={@objetivo} sale={@sale} devolution={@devolution} profit={@profit} nfs={@invoices_count} realizado_hoje_formatted={@realizado_hoje_formatted} animate_sale={@animate_sale} animate_devolution={@animate_devolution} animate_profit={@animate_profit} />
          </div>

          <!-- Coluna direita: Card Realizado Mensal -->
          <div class="flex-1 w-full lg:w-5/12 flex">
            <div class="bg-white rounded-xl shadow-lg border border-gray-100 p-3 sm:p-4 transition-all duration-300 hover:shadow-xl hover:scale-[1.01] w-full flex flex-col">
              <div class="text-center mb-3">
                <h2 class="text-xs sm:text-sm font-bold text-blue-700 mb-1 flex items-center justify-center gap-1.5">
                  <svg xmlns='http://www.w3.org/2000/svg' class='h-4 w-4 text-blue-600' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true"><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M13 16h-1v-4h-1m4 0h-1v-4h-1m4 0h-1v-4h-1' /></svg>
                  Realizado até ontem
                </h2>
              </div>

              <div class="flex flex-col items-center justify-center gap-3 flex-1">
                <!-- Gráfico Circular -->
                <div class="flex justify-center w-full flex-1 items-center">
                  <%= if @loading do %>
                    <div class="radial-progress animate-spin" style={"--value: 20; --size: 10rem;"} role="status" aria-label="Carregando gráfico">
                      <span class="text-xs text-gray-500">Carregando...</span>
                    </div>
                  <% else %>
                    <.radial_progress
                      value={@percentual_sale_capped}
                      size="10rem"
                      thickness="0.4rem"
                      label={@percentual_sale_display}
                      label_bottom="mensal"
                    />
                  <% end %>
                </div>

                <!-- Cards horizontais -->
                <div class="flex flex-col sm:flex-row gap-2 w-full justify-center items-center">
                  <div class="flex-1 min-w-[90px] bg-gray-50 rounded-lg p-2 flex flex-col items-center shadow-sm border border-gray-100 hover:shadow-md transition-shadow duration-200">
                    <div class="flex items-center gap-1 text-[10px] text-gray-600 mb-0.5">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 text-gray-400' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true"><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' /></svg>
                      Objetivo
                    </div>
                    <div class="font-mono text-xs font-semibold text-gray-900 truncate w-full text-center">{@objetivo_mensal}</div>
                  </div>
                  <div class="flex-1 min-w-[90px] bg-blue-50 rounded-lg p-2 flex flex-col items-center shadow-sm border border-blue-100 hover:shadow-md transition-shadow duration-200">
                    <div class="flex items-center gap-1 text-[10px] text-blue-700 mb-0.5">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 text-blue-400' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true"><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M3 17l6-6 4 4 8-8' /></svg>
                      Vendas
                    </div>
                    <div class="font-mono text-xs font-semibold text-blue-700 truncate w-full text-center">{@sale_mensal}</div>
                  </div>
                  <div class="flex-1 min-w-[90px] bg-red-50 rounded-lg p-2 flex flex-col items-center shadow-sm border border-red-100 hover:shadow-md transition-shadow duration-200">
                    <div class="flex items-center gap-1 text-[10px] text-red-700 mb-0.5">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 text-red-400' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true"><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M6 18L18 6M6 6l12 12' /></svg>
                      Devoluções
                    </div>
                    <div class="font-mono text-xs font-semibold text-red-700 truncate w-full text-center">{@devolution_mensal}</div>
                  </div>
                  <%= if @show_goal_remaining do %>
                    <div class="flex-1 min-w-[90px] bg-green-50 rounded-lg p-2 flex flex-col items-center shadow-sm border border-green-100 hover:shadow-md transition-shadow duration-200">
                      <div class="flex items-center gap-1 text-[10px] text-green-700 mb-0.5">
                        <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 text-green-400' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true"><path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' /></svg>
                        Falta
                      </div>
                      <div class="font-mono text-xs font-semibold text-green-700 truncate w-full text-center">{@goal_remaining_display}</div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Mensagem de erro se API estiver offline -->
      <%= if @api_status == :error and @api_error do %>
        <div class="mt-6 sm:mt-8 p-4 bg-red-50 border border-red-200 rounded-lg max-w-md mx-3 sm:mx-8 shadow-md" role="alert">
          <div class="flex items-center">
            <svg class="w-5 h-5 text-red-500 mr-2 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span class="text-sm text-red-700">
              Erro na API: {@api_error}
            </span>
          </div>
        </div>
      <% end %>

      <.supervisor_modal show={@show_drawer} supervisor_data={@supervisor_data} loading={@supervisor_loading} on_close="close_drawer" />

    </div>
    """
  end
end
