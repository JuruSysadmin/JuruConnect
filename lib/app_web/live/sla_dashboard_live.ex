defmodule AppWeb.SLADashboardLive do
  @moduledoc """
  LiveView para dashboard de monitoramento de SLA.
  """

  use AppWeb, :live_view

  alias App.SLAs

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Agendar verificação periódica de SLA
      schedule_sla_check()

      # Configurar timer para atualização automática
      Process.send_after(self(), :refresh_data, 30000) # 30 segundos
    end

    {:ok,
     socket
     |> assign(:loading, true)
     |> assign(:stats, %{})
     |> assign(:critical_alerts, [])
     |> assign(:warning_alerts, [])
     |> load_dashboard_data()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_event("resolve_alert", %{"alert_id" => alert_id}, socket) do
    case SLAs.get_sla_alert(alert_id) do
      {:ok, alert} ->
        case SLAs.resolve_sla_alert(alert) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Alerta resolvido com sucesso")
             |> load_dashboard_data()}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Erro ao resolver alerta")}
        end
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Alerta não encontrado")}
    end
  end

  @impl true
  def handle_event("cancel_alert", %{"alert_id" => alert_id}, socket) do
    case SLAs.get_sla_alert(alert_id) do
      {:ok, alert} ->
        case SLAs.cancel_sla_alert(alert) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Alerta cancelado com sucesso")
             |> load_dashboard_data()}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Erro ao cancelar alerta")}
        end
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Alerta não encontrado")}
    end
  end

  @impl true
  def handle_event("force_sla_check", _params, socket) do
    App.Jobs.SLACheckJob.schedule_immediate_sla_check()

    {:noreply,
     socket
     |> put_flash(:info, "Verificação de SLA agendada")
     |> load_dashboard_data()}
  end

  @impl true
  def handle_info(:refresh_data, socket) do
    # Agendar próxima atualização
    Process.send_after(self(), :refresh_data, 30000)

    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-6">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">Dashboard SLA</h1>
              <p class="mt-1 text-sm text-gray-500">Monitoramento de Service Level Agreement</p>
            </div>
            <div class="flex space-x-3">
              <button
                phx-click="force_sla_check"
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
                Verificar SLA
              </button>
              <button
                phx-click="refresh"
                class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
                Atualizar
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Loading State -->
      <%= if @loading do %>
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="flex justify-center items-center h-64">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
          </div>
        </div>
      <% else %>
        <!-- Main Content -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

          <!-- Stats Overview -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
            <!-- Total Alertas -->
            <div class="bg-white overflow-hidden shadow rounded-lg">
              <div class="p-5">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <svg class="h-6 w-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                    </svg>
                  </div>
                  <div class="ml-5 w-0 flex-1">
                    <dl>
                      <dt class="text-sm font-medium text-gray-500 truncate">Total de Alertas</dt>
                      <dd class="text-lg font-medium text-gray-900"><%= @stats.total_alerts %></dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>

            <!-- Alertas Ativos -->
            <div class="bg-white overflow-hidden shadow rounded-lg">
              <div class="p-5">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <svg class="h-6 w-6 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                  </div>
                  <div class="ml-5 w-0 flex-1">
                    <dl>
                      <dt class="text-sm font-medium text-gray-500 truncate">Alertas Ativos</dt>
                      <dd class="text-lg font-medium text-gray-900"><%= @stats.active_alerts %></dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>

            <!-- Alertas Críticos -->
            <div class="bg-white overflow-hidden shadow rounded-lg">
              <div class="p-5">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <svg class="h-6 w-6 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                    </svg>
                  </div>
                  <div class="ml-5 w-0 flex-1">
                    <dl>
                      <dt class="text-sm font-medium text-gray-500 truncate">Alertas Críticos</dt>
                      <dd class="text-lg font-medium text-red-600"><%= @stats.critical_alerts %></dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>

            <!-- Taxa de Conformidade -->
            <div class="bg-white overflow-hidden shadow rounded-lg">
              <div class="p-5">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <svg class="h-6 w-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                  </div>
                  <div class="ml-5 w-0 flex-1">
                    <dl>
                      <dt class="text-sm font-medium text-gray-500 truncate">Conformidade SLA</dt>
                      <dd class="text-lg font-medium text-green-600"><%= @stats.sla_compliance_rate %>%</dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Alertas Críticos -->
          <%= if length(@critical_alerts) > 0 do %>
            <div class="bg-white shadow rounded-lg mb-8">
              <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4 flex items-center">
                  <svg class="w-5 h-5 text-red-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                  </svg>
                  Alertas Críticos (<%= length(@critical_alerts) %>)
                </h3>
                <div class="space-y-4">
                  <%= for alert <- @critical_alerts do %>
                    <div class="border-l-4 border-red-400 bg-red-50 p-4 rounded-r-lg">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <div class="flex items-center">
                            <h4 class="text-sm font-medium text-red-800">
                              Tratativa #<%= alert.treaty.treaty_code %>
                            </h4>
                            <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                              <%= String.upcase(alert.priority) %>
                            </span>
                          </div>
                          <p class="mt-1 text-sm text-red-700">
                            <%= alert.treaty.title %>
                          </p>
                          <p class="mt-1 text-xs text-red-600">
                            Alerta criado em <%= format_datetime(alert.alerted_at) %>
                          </p>
                        </div>
                        <div class="flex space-x-2 ml-4">
                          <button
                            phx-click="resolve_alert"
                            phx-value-alert_id={alert.id}
                            class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700"
                          >
                            Resolver
                          </button>
                          <button
                            phx-click="cancel_alert"
                            phx-value-alert_id={alert.id}
                            class="inline-flex items-center px-3 py-1 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
                          >
                            Cancelar
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Alertas de Warning -->
          <%= if length(@warning_alerts) > 0 do %>
            <div class="bg-white shadow rounded-lg mb-8">
              <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4 flex items-center">
                  <svg class="w-5 h-5 text-yellow-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                  Alertas de Aviso (<%= length(@warning_alerts) %>)
                </h3>
                <div class="space-y-4">
                  <%= for alert <- @warning_alerts do %>
                    <div class="border-l-4 border-yellow-400 bg-yellow-50 p-4 rounded-r-lg">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <div class="flex items-center">
                            <h4 class="text-sm font-medium text-yellow-800">
                              Tratativa #<%= alert.treaty.treaty_code %>
                            </h4>
                            <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                              <%= String.upcase(alert.priority) %>
                            </span>
                          </div>
                          <p class="mt-1 text-sm text-yellow-700">
                            <%= alert.treaty.title %>
                          </p>
                          <p class="mt-1 text-xs text-yellow-600">
                            Alerta criado em <%= format_datetime(alert.alerted_at) %>
                          </p>
                        </div>
                        <div class="flex space-x-2 ml-4">
                          <button
                            phx-click="resolve_alert"
                            phx-value-alert_id={alert.id}
                            class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700"
                          >
                            Resolver
                          </button>
                          <button
                            phx-click="cancel_alert"
                            phx-value-alert_id={alert.id}
                            class="inline-flex items-center px-3 py-1 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50"
                          >
                            Cancelar
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Estatísticas Detalhadas -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <!-- Distribuição por Categoria -->
            <div class="bg-white shadow rounded-lg">
              <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Alertas por Categoria</h3>
                <div class="space-y-3">
                  <%= for category <- @stats.alerts_by_category do %>
                    <div class="flex justify-between items-center">
                      <span class="text-sm font-medium text-gray-700">
                        <%= category.category %>
                      </span>
                      <span class="text-sm text-gray-500">
                        <%= category.count %> alertas
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- Distribuição por Prioridade -->
            <div class="bg-white shadow rounded-lg">
              <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Alertas por Prioridade</h3>
                <div class="space-y-3">
                  <%= for priority <- @stats.alerts_by_priority do %>
                    <div class="flex justify-between items-center">
                      <span class="text-sm font-medium text-gray-700">
                        <%= String.capitalize(priority.priority) %>
                      </span>
                      <span class="text-sm text-gray-500">
                        <%= priority.count %> alertas
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Funções auxiliares

  defp load_dashboard_data(socket) do
    stats = SLAs.get_sla_stats()
    critical_alerts = SLAs.get_critical_alerts(10)
    warning_alerts = SLAs.get_warning_alerts(20)

    socket
    |> assign(:loading, false)
    |> assign(:stats, stats)
    |> assign(:critical_alerts, critical_alerts)
    |> assign(:warning_alerts, warning_alerts)
  end

  defp schedule_sla_check do
    App.Jobs.SLACheckJob.schedule_sla_check()
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0, 16)
  end
end
