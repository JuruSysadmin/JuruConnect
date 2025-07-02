defmodule AppWeb.HealthLive.Dashboard do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "health_check:status")
      :timer.send_interval(30_000, self(), :refresh_data)
    end

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:health_data, %{})
      |> load_health_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:health_status_updated, health_data}, socket) do
    socket =
      socket
      |> assign(:health_data, health_data)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_data, socket) do
    {:noreply, load_health_data(socket)}
  end

  @impl true
  def handle_event("trigger_check", _params, socket) do
    App.HealthCheck.check_now()

    socket =
      socket
      |> assign(:loading, true)
      |> put_flash(:info, "Verificação de saúde iniciada...")

    {:noreply, socket}
  end

  defp load_health_data(socket) do
    detailed_status = App.HealthCheck.get_detailed_status()

    socket
    |> assign(:health_data, format_health_data(detailed_status))
    |> assign(:loading, false)
  end

  defp format_health_data(status) do
    %{
      api_status: status.api_status,
      last_check: status.last_check,
      uptime_percentage: status.uptime_percentage,
      error_count: status.error_count,
      response_time: status.response_time,
      endpoints: status.endpoints_status || %{},
      status_text: get_status_text(status.api_status)
    }
  end

  defp get_status_text(:healthy), do: "Saudável"
  defp get_status_text(:degraded), do: "Degradado"
  defp get_status_text(:unhealthy), do: "Indisponível"
  defp get_status_text(_), do: "Desconhecido"

  defp format_datetime(nil), do: "Nunca"
  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0..18)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <!-- Topbar Moderna -->
      <div class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16">
            <!-- Logo e Título -->
            <div class="flex items-center space-x-4">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-gradient-to-r from-blue-500 to-indigo-600 rounded-lg flex items-center justify-center">
                  <span class="text-white font-bold text-sm">HC</span>
                </div>
              </div>
              <div>
                <h1 class="text-xl font-semibold text-gray-900">Health Check Monitor</h1>
                <p class="text-sm text-gray-500">Monitoramento em Tempo Real • API Externa</p>
              </div>
            </div>

            <!-- Status Geral e Ações -->
            <div class="flex items-center space-x-6">
              <!-- Indicador de Status Principal -->
              <div class="flex items-center space-x-3 px-3 py-1 rounded-full bg-gray-50">
                <div class="flex items-center space-x-2">
                  <%= case @health_data[:api_status] do %>
                    <% :healthy -> %>
                      <div class="w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
                      <span class="text-sm font-medium text-green-700">Operacional</span>
                    <% :degraded -> %>
                      <div class="w-3 h-3 bg-yellow-400 rounded-full animate-pulse"></div>
                      <span class="text-sm font-medium text-yellow-700">Degradado</span>
                    <% :unhealthy -> %>
                      <div class="w-3 h-3 bg-red-400 rounded-full animate-pulse"></div>
                      <span class="text-sm font-medium text-red-700">Indisponível</span>
                    <% _ -> %>
                      <div class="w-3 h-3 bg-gray-400 rounded-full"></div>
                      <span class="text-sm font-medium text-gray-600">Verificando...</span>
                  <% end %>
                </div>
              </div>

              <!-- Uptime Badge -->
              <div class="text-center">
                <div class="text-lg font-semibold text-green-600">
                  <%= (@health_data[:uptime_percentage] || 0) |> Float.round(1) %>%
                </div>
                <div class="text-xs text-gray-500 uppercase tracking-wide">Uptime</div>
              </div>

              <!-- Botão de Ação -->
              <button
                phx-click="trigger_check"
                class={[
                  "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm transition-colors duration-200",
                  if(@loading,
                    do: "bg-gray-400 text-white cursor-not-allowed",
                    else: "bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  )
                ]}
                disabled={@loading}
              >
                <%= if @loading do %>
                  <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Verificando...
                <% else %>
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                  </svg>
                  Verificar Agora
                <% end %>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Conteúdo Principal -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Cards de Métricas -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <!-- Tempo de Resposta -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600 mb-1">Tempo de Resposta</p>
                <p class="text-2xl font-bold text-blue-600">
                  <%= if @health_data[:response_time] do %>
                    <%= @health_data[:response_time] %><span class="text-lg text-gray-500">ms</span>
                  <% else %>
                    <span class="text-gray-400">--</span>
                  <% end %>
                </p>
              </div>
              <div class="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
                <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                </svg>
              </div>
            </div>
          </div>

          <!-- Erros -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600 mb-1">Erros Consecutivos</p>
                <p class={[
                  "text-2xl font-bold",
                  if((@health_data[:error_count] || 0) > 0, do: "text-red-600", else: "text-green-600")
                ]}>
                  <%= @health_data[:error_count] || 0 %>
                </p>
              </div>
              <div class={[
                "w-12 h-12 rounded-lg flex items-center justify-center",
                if((@health_data[:error_count] || 0) > 0, do: "bg-red-100", else: "bg-green-100")
              ]}>
                <%= if (@health_data[:error_count] || 0) > 0 do %>
                  <svg class="w-6 h-6 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.734-.833-2.464 0L4.35 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
                  </svg>
                <% else %>
                  <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Última Verificação -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-100 p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-600 mb-1">Última Verificação</p>
                <p class="text-sm text-gray-900 font-medium truncate">
                  <%= format_datetime(@health_data[:last_check]) %>
                </p>
              </div>
              <div class="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center flex-shrink-0">
                <svg class="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
              </div>
            </div>
          </div>
        </div>

        <!-- Status Detalhado -->
        <div class="bg-white rounded-xl shadow-sm border border-gray-100">
          <div class="px-6 py-4 border-b border-gray-100">
            <h3 class="text-lg font-semibold text-gray-900 flex items-center">
              <svg class="w-5 h-5 mr-2 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"></path>
              </svg>
              Detalhes do Sistema
            </h3>
          </div>
          <div class="px-6 py-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <dt class="text-sm font-medium text-gray-500">Endpoint Base</dt>
                <dd class="mt-1 text-sm text-gray-900 font-mono bg-gray-50 px-2 py-1 rounded">
                  http://10.1.1.212:8065/api/v1
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Status Atual</dt>
                <dd class="mt-1">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    case @health_data[:api_status] do
                      :healthy -> "bg-green-100 text-green-800"
                      :degraded -> "bg-yellow-100 text-yellow-800"
                      :unhealthy -> "bg-red-100 text-red-800"
                      _ -> "bg-gray-100 text-gray-800"
                    end
                  ]}>
                    <%= @health_data[:status_text] || "Verificando..." %>
                  </span>
                </dd>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
