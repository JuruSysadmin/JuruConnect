defmodule AppWeb.MonthlyMetricsLive do
    @moduledoc """
    LiveView para métricas mensais do dashboard.

    Responsável por exibir o gráfico circular mensal, objetivos, vendas e devoluções mensais.
    """

    use AppWeb, :live_view

    import AppWeb.DashboardUtils
    import AppWeb.DashboardComponents
    import AppWeb.DashboardState

    @impl Phoenix.LiveView
    def mount(_params, _session, socket) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
      end

      socket = assign(socket, %{
        loading: true,
        percentual_sale: 0.0,
        percentual_sale_display: "0,00%",
        percentual_sale_capped: 0,
        objetivo_mensal: "R$ 0,00",
        sale_mensal: "R$ 0,00",
        ticket_medio_mensal: "R$ 0,00",
        monthly_sale_value: 0.0,
        monthly_goal_value: 0.0,
        goal_exceeded: false,
        goal_remaining_display: "R$ 0,00",
        show_goal_remaining: false
      })

      {:ok, socket}
    end

    @impl Phoenix.LiveView
    def handle_info({:dashboard_updated, data}, socket) do
      data = convert_keys_to_atoms(data)

      socket = socket
      |> assign_monthly_data(data)
      |> assign_template_values()
      |> assign(%{loading: false})

      socket = push_event(socket, "update-gauge-monthly", %{value: socket.assigns.percentual_sale})

      {:noreply, socket}
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      ~H"""
      <div class="w-full flex min-w-0">
        <div class="card bg-base-100/80 backdrop-blur-xl shadow-lg border border-base-300/50 p-3 sm:p-4 transition-all duration-300 hover:shadow-xl w-full h-full flex flex-col min-w-0">
        <div class="text-center mb-2">
          <h2 class="card-title text-xs sm:text-sm font-bold text-base-content mb-1 flex items-center justify-center gap-1 truncate">
              <svg xmlns='http://www.w3.org/2000/svg' class='h-3 w-3 sm:h-4 sm:w-4 flex-shrink-0' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M13 16h-1v-4h-1m4 0h-1v-4h-1m4 0h-1v-4h-1' />
              </svg>
              Realizado até ontem
            </h2>
          </div>

          <div class="flex flex-col items-center gap-1.5 flex-1 justify-between min-h-0">
            <!-- Gráfico Circular -->
            <div class="flex flex-col items-center justify-center w-full gap-2">
              <%= if @loading do %>
                <div class="radial-progress animate-spin" style={"--value: 20; --size: 10rem;"} role="status" aria-label="Carregando gráfico">
                  <span class="text-xs text-base-content/70">Carregando...</span>
                </div>
              <% else %>
                <.radial_progress
                  value={@percentual_sale_capped}
                  size="10rem"
                  thickness="0.5rem"
                  label={@percentual_sale_display}
                  label_bottom="mensal"
                  class="text-base-content"
                />
              <% end %>
            </div>

            <!-- Cards horizontais -->
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 sm:gap-2.5 w-full">
              <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                  <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                    <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' />
                  </svg>
                  Objetivo Mensal
                </div>
                <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">{@objetivo_mensal}</div>
              </div>

              <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                  <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                    <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M3 17l6-6 4 4 8-8' />
                  </svg>
                  Vendas Mensal
                </div>
                <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">{@sale_mensal}</div>
              </div>

              <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                  <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                    <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z' />
                  </svg>
                  Ticket Médio Mensal
                </div>
                <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">{@ticket_medio_mensal}</div>
              </div>

              <%= if @show_goal_remaining do %>
                <%= if @goal_exceeded do %>
                <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                  <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                        <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M13 7h8m0 0v8m0-8l-8 8-4-4-6 6' />
                      </svg>
                      Excedente
                    </div>
                  <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">+{@goal_remaining_display}</div>
                  </div>
                <% else %>
                <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                  <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                      <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                        <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M12 8v4l3 3' />
                      </svg>
                      Falta
                    </div>
                  <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">{@goal_remaining_display}</div>
                  </div>
                <% end %>
              <% else %>
                <div class="bg-base-200/80 backdrop-blur-sm rounded-md p-2 sm:p-2.5 flex flex-col items-center shadow-sm border border-base-300/50 overflow-hidden">
                  <div class="flex items-center gap-1.5 text-xs sm:text-sm text-base-content mb-1.5">
                    <svg xmlns='http://www.w3.org/2000/svg' class='h-2.5 w-2.5 sm:h-3 sm:w-3' fill='none' viewBox='0 0 24 24' stroke='currentColor' aria-hidden="true">
                      <path stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M9 12l2 2 4-4' />
                    </svg>
                    Status
                  </div>
                  <div class="font-mono text-[13px] sm:text-sm font-bold text-base-content text-center truncate w-full">N/A</div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      """
    end

    # Funções privadas

    defp assign_monthly_data(socket, data) do
      assign(socket, %{
        percentual_sale: Map.get(data, :percentualSale, 0.0),
        monthly_sale_value: Map.get(data, :sale_mensal, 0.0),
        monthly_goal_value: Map.get(data, :objetivo_mensal, 0.0),
        objetivo_mensal: format_money(Map.get(data, :objetivo_mensal, 0.0)),
        sale_mensal: format_money(Map.get(data, :sale_mensal, 0.0)),
        ticket_medio_mensal: format_money(Map.get(data, :ticket_medio_mensal, 0.0))
      })
    end

    defp assign_template_values(socket) do
      socket.assigns
      |> Map.get(:percentual_sale, 0.0)
      |> calculate_monthly_template_values(
        socket.assigns.monthly_sale_value,
        socket.assigns.monthly_goal_value
      )
      |> then(&assign(socket, &1))
    end
  end
