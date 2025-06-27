defmodule AppWeb.DashboardResumoLive do
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
    # Adiciona notificação à lista
    new_notification = %{
      id: System.unique_integer([:positive]),
      store_name: goal_data.store_name,
      achieved: goal_data.achieved,
      target: goal_data.target,
      percentage: goal_data.percentage,
      timestamp: goal_data.timestamp
    }

    updated_notifications = [new_notification | socket.assigns.notifications]
    |> Enum.take(5) # Mantém apenas as 5 mais recentes

    socket =
      socket
      |> assign(
        notifications: updated_notifications,
        show_celebration: true
      )
      |> push_event("goal-achieved", %{
        store_name: goal_data.store_name,
        achieved: AppWeb.DashboardUtils.format_money(goal_data.achieved)
      })

    # Remove a celebração após 5 segundos
    Process.send_after(self(), :hide_celebration, 5000)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:hide_celebration, socket) do
    {:noreply, assign(socket, show_celebration: false)}
  end

  # Funções privadas organizadas por responsabilidade

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
        assign_success_data(socket, data_with_atom_keys)
        |> assign(
          api_status: state.api_status,
          last_update: state.last_update,
          loading: false
        )

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

  defp convert_keys_to_atoms(data) when is_map(data) do
    for {k, v} <- data, into: %{}, do: {String.to_atom(k), v}
  end
  defp convert_keys_to_atoms(_), do: %{}

  defp assign_success_data(socket, data) do
    percentual_num = calculate_percentual_number(data)
    sale_num = Map.get(data, :sale, 0.0)
    objetivo_num = Map.get(data, :objetivo, 0.0)

    assigns = [
      sale: format_money(sale_num),
      cost: format_money(Map.get(data, :cost, 0.0)),
      devolution: format_money(Map.get(data, :devolution, 0.0)),
      objetivo: format_money(objetivo_num),
      profit: format_percent(Map.get(data, :profit, 0.0)),
      percentual: format_percent(Map.get(data, :percentual, 0.0)),
      percentual_num: percentual_num,
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
      value when is_number(value) -> value
      value when is_binary(value) -> parse_percent_to_number(value)
      _ -> 0.0
    end
  end

  defp calculate_remaining_amount(assigns) do
    sale_value = Map.get(assigns, :sale_num, 0.0)
    objetivo_value = Map.get(assigns, :objetivo_num, 0.0)
    max(objetivo_value - sale_value, 0.0)
  end

  defp get_companies_data(data) do
    case Map.get(data, :companies) do
      companies when is_list(companies) -> companies
      _ -> []
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
    </style>
    <div id="dashboard-main" class="min-h-screen bg-white" phx-hook="GoalCelebration">
      <!-- Notificações de Meta Atingida -->
      <%= if @show_celebration do %>
        <div class="fixed inset-0 z-50 pointer-events-none">
          <!-- Confetti Effect -->
          <div class="absolute top-0 left-1/4 w-2 h-2 bg-yellow-400 confetti" style="animation-delay: 0s;"></div>
          <div class="absolute top-0 left-1/2 w-2 h-2 bg-green-400 confetti" style="animation-delay: 0.2s;"></div>
          <div class="absolute top-0 left-3/4 w-2 h-2 bg-blue-400 confetti" style="animation-delay: 0.4s;"></div>
          <div class="absolute top-0 left-1/3 w-2 h-2 bg-red-400 confetti" style="animation-delay: 0.6s;"></div>
          <div class="absolute top-0 left-2/3 w-2 h-2 bg-purple-400 confetti" style="animation-delay: 0.8s;"></div>
        </div>
      <% end %>

      <!-- Painel de Notificações -->
      <div class="fixed top-4 right-4 z-40 space-y-2">
        <%= for notification <- @notifications do %>
          <div class="bg-gradient-to-r from-green-500 to-emerald-600 text-white p-4 rounded-lg shadow-2xl max-w-sm bounce-in">
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0">
                <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
              </div>
              <div class="flex-1">
                <h4 class="font-bold text-lg">🎉 Meta Atingida!</h4>
                <p class="text-sm opacity-90"><%= notification.store_name %></p>
                <p class="text-xs opacity-75">
                  <%= AppWeb.DashboardUtils.format_money(notification.achieved) %>
                  (<%= :erlang.float_to_binary(notification.percentage, decimals: 1) %>%)
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Header com status da API -->
      <div class="flex items-center justify-between w-full px-8 py-6 mb-6">
        <h1 class="text-4xl font-extrabold text-gray-900 tracking-tight">JURUNENSE HOME CENTER</h1>
        <div class="flex items-center space-x-4">
          <%= if @loading do %>
            <div class="flex items-center space-x-2">
              <div class="w-3 h-3 rounded-full bg-blue-500 animate-pulse"></div>
              <span class="text-sm text-gray-600">Carregando...</span>
            </div>
          <% else %>
          <div class="flex items-center space-x-2">
              <div class={["w-3 h-3 rounded-full",
                if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")
              ]}></div>
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
            <span class="text-xs text-gray-400">
              Atualizado: <%= Calendar.strftime(@last_update, "%H:%M:%S") %>
            </span>
          <% end %>
        </div>
      </div>

      <!-- Layout principal dividido -->
      <div class="flex gap-6 px-8">
        <!-- Coluna esquerda: Cards e Gráficos -->
        <div class="flex-1 space-y-6">
          <!-- Cards de métricas -->
          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
            <.card title="Faturamento" value={@sale} subtitle="Venda Bruta" icon_bg="bg-green-50">
              <:icon>
                <svg class="w-6 h-6 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 1.343-3 3s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3zm0 0V4m0 16v-4"/>
                </svg>
              </:icon>
            </.card>

            <.card title="Custo" value={@cost} subtitle="Custo Total" icon_bg="bg-blue-50">
              <:icon>
                <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3"/>
                </svg>
              </:icon>
            </.card>

            <.card title="Devoluções" value={@devolution} subtitle="Total Devolvido" icon_bg="bg-red-50">
              <:icon>
                <svg class="w-6 h-6 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/>
                </svg>
              </:icon>
            </.card>

            <.card title="Objetivo" value={@objetivo} subtitle="Meta do Período" icon_bg="bg-yellow-50">
              <:icon>
                <svg class="w-6 h-6 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a5 5 0 00-10 0v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2z"/>
                </svg>
              </:icon>
            </.card>

            <.card title="Lucro" value={@profit} subtitle="Margem Bruta" icon_bg="bg-green-100">
              <:icon>
                <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 1.343-3 3s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3zm0 0V4m0 16v-4"/>
                </svg>
              </:icon>
            </.card>

            <.card title="NFS" value={@nfs} subtitle="Notas Fiscais" icon_bg="bg-purple-50">
              <:icon>
                <svg class="w-6 h-6 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                </svg>
              </:icon>
            </.card>
          </div>

          <!-- Seção de Metas em Tempo Real -->
          <div class="bg-white rounded-2xl shadow-lg border border-gray-100 p-6">
            <div class="text-center mb-6">
              <h2 class="text-xl font-bold text-gray-900 mb-2">Progresso da Meta</h2>
              <p class="text-gray-600">Acompanhamento em tempo real do objetivo diario</p>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-center">
              <!-- Gauge Chart -->
              <div class="flex justify-center">
                <%= if @loading do %>
                  <div class="w-48 h-48 flex items-center justify-center">
                    <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
                  </div>
                <% else %>
                  <div class="relative">
                    <canvas
                      id="gauge-chart"
                      phx-hook="GaugeChart"
                      phx-update="ignore"
                      data-value={@percentual_num}
                      class="w-48 h-48"
                    >
                    </canvas>
                    <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                      <span class="text-3xl font-bold text-gray-800"><%= @percentual %></span>
                      <span class="text-xs font-medium text-gray-500 mt-1">da meta atingida</span>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Informações da Meta -->
              <div class="space-y-4">
                <div class="grid grid-cols-1 gap-3">
                  <div class="bg-green-50 p-3 rounded-lg border border-green-200">
                    <div class="text-sm font-medium text-green-800 mb-1">Faturamento Atual</div>
                    <div class="text-xl font-bold text-green-900"><%= @sale %></div>
                  </div>

                  <div class="bg-blue-50 p-3 rounded-lg border border-blue-200">
                    <div class="text-sm font-medium text-blue-800 mb-1">Meta do Dia</div>
                    <div class="text-xl font-bold text-blue-900"><%= @objetivo %></div>
                  </div>
                </div>

                <%= if @percentual_num >= 100 do %>
                  <div class="bg-green-100 border border-green-300 rounded-lg p-3">
                    <div class="flex items-center">
                      <svg class="w-4 h-4 text-green-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                      </svg>
                      <span class="text-green-800 font-medium text-sm">🎉 Parabéns! Meta atingida!</span>
                    </div>
                  </div>
                <% else %>
                  <% remaining = calculate_remaining_amount(assigns) %>
                  <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
                    <div class="text-sm text-blue-800">
                      <strong>Faltam:</strong> <%= format_money(remaining) %> para atingir a meta
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <!-- Coluna direita: Tabela de Performance das Lojas -->
        <div class="w-2/3">
          <div class="bg-white rounded-3xl shadow-2xl border border-gray-100 overflow-hidden">
            <!-- Header da Tabela -->
            <div class="bg-gradient-to-r from-blue-600 to-blue-900 px-8 py-6">
            </div>

            <!-- Filtros e Controles -->
            <div class="bg-gray-50 px-8 py-4 border-b border-gray-200">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div class="flex items-center space-x-4">
                  <div class="flex items-center space-x-2">
                    <div class="w-3 h-3 rounded-full bg-green-500 animate-pulse"></div>
                    <span class="text-sm text-gray-600">Meta Atingida</span>
                  </div>
                  <div class="flex items-center space-x-2">
                    <div class="w-3 h-3 rounded-full bg-red-500"></div>
                    <span class="text-sm text-gray-600">Abaixo da Meta</span>
                  </div>
                  <div class="flex items-center space-x-2">
                    <div class="w-3 h-3 rounded-full bg-gray-400"></div>
                    <span class="text-sm text-gray-600">Sem Vendas</span>
                  </div>
                </div>
                <div class="text-sm text-gray-500">
                  <%= length(@lojas_data) %> lojas ativas
                </div>
              </div>
            </div>

            <!-- Tabela -->
            <div class="overflow-x-auto">
              <table class="w-full animate-fade-in-scale">
                <thead class="bg-gradient-to-r from-gray-50 to-gray-100">
                  <tr>
                    <th class="text-left py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">
                      <div class="flex items-center space-x-2">
                        <svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/>
                        </svg>
                        <span>Loja</span>
                      </div>
                    </th>
                    <th class="text-right py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">Meta Dia</th>
                    <th class="text-right py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">Meta Hora</th>
                    <th class="text-center py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">NFs</th>
                    <th class="text-right py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">Venda Dia</th>
                    <th class="text-center py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">% Hora</th>
                    <th class="text-center py-4 px-6 font-bold text-gray-800 uppercase tracking-wider text-sm">% Dia</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= if @loading do %>
                    <%= for i <- 1..5 do %>
                      <tr class="animate-pulse">
                        <td class="py-4 px-6">
                          <div class="flex items-center space-x-4">
                            <div class="w-4 h-4 bg-gray-300 rounded-full shimmer-effect"></div>
                            <div class="h-4 bg-gray-300 rounded w-48 shimmer-effect"></div>
                          </div>
                        </td>
                        <td class="py-4 px-6"><div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div></td>
                        <td class="py-4 px-6"><div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div></td>
                        <td class="py-4 px-6"><div class="h-6 bg-gray-300 rounded-full w-12 mx-auto shimmer-effect"></div></td>
                        <td class="py-4 px-6"><div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div></td>
                        <td class="py-4 px-6"><div class="h-6 bg-gray-300 rounded-full w-16 mx-auto shimmer-effect"></div></td>
                        <td class="py-4 px-6"><div class="h-6 bg-gray-300 rounded-full w-16 mx-auto shimmer-effect"></div></td>
                      </tr>
                    <% end %>
                  <% else %>
                    <%= for {loja, index} <- Enum.with_index(@lojas_data) do %>
                      <tr class={[
                        "group hover:bg-gradient-to-r hover:from-blue-50 hover:to-indigo-50 transition-all duration-300 transform hover:scale-[1.01] hover:shadow-md animate-slide-in-up table-row-stagger",
                        if(rem(index, 2) == 0, do: "bg-white", else: "bg-gray-50/50")
                      ]} style={"--row-index: #{index}"}>
                        <td class="py-4 px-6">
                          <div class="flex items-center space-x-4">
                            <div class={[
                              "w-4 h-4 rounded-full relative overflow-hidden transition-all duration-300",
                              case loja.status do
                                :atingida_hora -> "bg-green-500 shadow-lg shadow-green-500/30"
                                :abaixo_meta -> "bg-red-500 shadow-lg shadow-red-500/30"
                                :sem_vendas -> "bg-gray-400"
                                _ -> "bg-yellow-500 shadow-lg shadow-yellow-500/30"
                              end
                            ]}>
                              <%= if loja.status == :atingida_hora do %>
                                <div class="absolute inset-0 bg-green-400 animate-ping opacity-75"></div>
                                <div class="absolute inset-0 bg-gradient-to-r from-green-300 to-emerald-400 animate-pulse"></div>
                              <% end %>
                              <%= if loja.perc_hora >= 120 do %>
                                <div class="absolute -inset-1 bg-gradient-to-r from-yellow-400 to-orange-500 rounded-full animate-spin opacity-30"></div>
                              <% end %>
                            </div>
                            <div>
                              <div class="font-semibold text-gray-900 group-hover:text-blue-900 transition-colors">
                                <%= loja.nome %>
                              </div>
                              <div class="text-xs text-gray-500 mt-1">
                                ID: <%= loja.supervisor_id %>
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="text-right py-4 px-6">
                          <div class="font-mono text-gray-800 font-medium">
                            <%= format_money(loja.meta_dia) %>
                          </div>
                        </td>
                        <td class="text-right py-4 px-6">
                          <div class="font-mono text-gray-800 font-medium">
                            <%= format_money(loja.meta_hora) %>
                          </div>
                        </td>
                        <td class="text-center py-4 px-6">
                          <span class={[
                            "inline-flex items-center px-3 py-1 rounded-full text-sm font-bold shadow-sm transition-all duration-300 transform hover:scale-110",
                            cond do
                              loja.qtde_nfs >= 100 -> "bg-gradient-to-r from-green-100 to-green-200 text-green-800 border border-green-300"
                              loja.qtde_nfs >= 50 -> "bg-gradient-to-r from-blue-100 to-blue-200 text-blue-800 border border-blue-300"
                              loja.qtde_nfs > 0 -> "bg-gradient-to-r from-yellow-100 to-yellow-200 text-yellow-800 border border-yellow-300"
                              true -> "bg-gradient-to-r from-gray-100 to-gray-200 text-gray-800 border border-gray-300"
                            end
                          ]}>
                            <%= loja.qtde_nfs %>
                          </span>
                        </td>
                        <td class="text-right py-4 px-6">
                          <div class={[
                            "font-mono font-bold transition-all duration-300",
                            if(loja.venda_dia >= loja.meta_dia, do: "text-green-700", else: "text-gray-800")
                          ]}>
                            <%= format_money(loja.venda_dia) %>
                          </div>
                        </td>
                        <td class="text-center py-4 px-6">
                          <div class="relative space-y-1">
                            <!-- Percentual -->
                            <div>
                              <span class={[
                                "inline-flex items-center px-3 py-2 rounded-full text-sm font-bold shadow-lg transition-all duration-300 transform hover:scale-110",
                                cond do
                                  loja.perc_hora >= 120 -> "bg-gradient-to-r from-emerald-500 to-green-500 text-white animate-pulse"
                                  loja.perc_hora >= 100 -> "bg-gradient-to-r from-green-400 to-green-500 text-white"
                                  loja.perc_hora >= 80 -> "bg-gradient-to-r from-yellow-400 to-orange-400 text-white"
                                  loja.perc_hora > 0 -> "bg-gradient-to-r from-red-400 to-red-500 text-white"
                                  true -> "bg-gradient-to-r from-gray-400 to-gray-500 text-white"
                                end
                              ]}>
                                <%= :erlang.float_to_binary(loja.perc_hora * 1.0, decimals: 1) %>%
                                <%= if loja.perc_hora >= 100 do %>
                                  <svg class="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                  </svg>
                                <% end %>
                              </span>
                            </div>
                            <!-- Valor em Reais da Meta Hora -->
                            <div class="text-xs font-mono">
                              <% valor_hora_reais = (loja.meta_hora * loja.perc_hora / 100) %>
                              <span class={[
                                "inline-flex items-center px-2 py-1 rounded text-xs font-semibold transition-all duration-300",
                                if(loja.perc_hora >= 100,
                                  do: "text-green-600 bg-green-50 border border-green-200",
                                  else: "text-red-600 bg-red-50 border border-red-200")
                              ]}>
                                <%= if loja.perc_hora >= 100 do %>
                                  ↗ <%= format_money(valor_hora_reais) %>
                                <% else %>
                                  ↘ <%= format_money(valor_hora_reais) %>
                                <% end %>
                              </span>
                            </div>
                          </div>
                        </td>
                        <td class="text-center py-4 px-6">
                          <div class="relative">
                            <!-- Barra de progresso de fundo -->
                            <div class="w-full bg-gray-200 rounded-full h-2 mb-2">
                              <div class={[
                                "h-2 rounded-full transition-all duration-700 ease-out",
                                cond do
                                  loja.perc_dia >= 80 -> "bg-gradient-to-r from-green-400 to-green-600"
                                  loja.perc_dia >= 60 -> "bg-gradient-to-r from-yellow-400 to-orange-500"
                                  loja.perc_dia > 0 -> "bg-gradient-to-r from-red-400 to-red-600"
                                  true -> "bg-gray-400"
                                end
                              ]} style={"width: #{min(loja.perc_dia, 100)}%"}></div>
                            </div>
                            <span class={[
                              "inline-flex items-center px-3 py-1 rounded-full text-sm font-bold shadow-md transition-all duration-300 transform hover:scale-110",
                              cond do
                                loja.perc_dia >= 80 -> "bg-gradient-to-r from-green-100 to-green-200 text-green-800 border border-green-300"
                                loja.perc_dia >= 60 -> "bg-gradient-to-r from-yellow-100 to-yellow-200 text-yellow-800 border border-yellow-300"
                                loja.perc_dia > 0 -> "bg-gradient-to-r from-red-100 to-red-200 text-red-800 border border-red-300"
                                true -> "bg-gradient-to-r from-gray-100 to-gray-200 text-gray-800 border border-gray-300"
                              end
                            ]}>
                              <%= :erlang.float_to_binary(loja.perc_dia * 1.0, decimals: 1) %>%
                            </span>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
                <!-- Footer com totais -->
                <tfoot>
                  <tr class="bg-gradient-to-r from-gray-800 to-gray-900 text-white">
                    <td class="py-4 px-6 font-bold text-lg">
                      <div class="flex items-center space-x-2">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
                        </svg>
                        <span>TOTAL GERAL</span>
                      </div>
                    </td>
                    <td class="text-right py-4 px-6 font-bold text-lg font-mono"><%= @objetivo %></td>
                    <td class="text-right py-4 px-6 font-bold text-lg font-mono">
                      <%= format_money(434761.80) %>
                    </td>
                    <td class="text-center py-4 px-6">
                      <span class="bg-blue-500 text-white px-3 py-2 rounded-full text-sm font-bold shadow-lg">
                        <%= @nfs %>
                      </span>
                    </td>
                    <td class="text-right py-4 px-6 font-bold text-lg font-mono"><%= @sale %></td>
                    <td class="text-center py-4 px-6">
                      <span class="bg-gradient-to-r from-green-400 to-green-600 text-white px-3 py-2 rounded-full text-sm font-bold shadow-lg animate-pulse">
                        108,56%
                      </span>
                    </td>
                    <td class="text-center py-4 px-6">
                      <span class={[
                        "px-3 py-2 rounded-full text-sm font-bold shadow-lg",
                        if(@percentual_num >= 60,
                          do: "bg-gradient-to-r from-yellow-400 to-orange-500 text-white",
                          else: "bg-gradient-to-r from-red-400 to-red-600 text-white")
                      ]}>
                        <%= @percentual %>
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
            <svg class="w-5 h-5 text-red-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
            <span class="text-sm text-red-700">
              Erro na API: <%= @api_error %>
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
