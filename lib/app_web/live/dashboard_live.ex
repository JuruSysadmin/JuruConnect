defmodule AppWeb.DashboardLive do
  @moduledoc """
  LiveView principal do dashboard do sistema JuruConnect.

  Responsável por exibir a interface inicial do dashboard, menus de navegação, atalhos para funcionalidades principais e informações do usuário logado.

  Serve como ponto de entrada visual para o ambiente administrativo e operacional do sistema.
  """
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-gray-50">
      <!-- Sidebar -->
      <div class="fixed left-0 top-0 h-full w-64 bg-white shadow-sm border-r border-gray-200 flex flex-col z-10">
        <!-- Header -->
        <div class="p-6 border-b border-gray-100">
          <div class="flex items-center space-x-3">
            <div class="w-10 h-10 bg-gradient-to-br from-blue-500 to-blue-600 rounded-lg flex items-center justify-center">
              <span class="text-white text-lg font-bold">J</span>
            </div>
            <div>
              <h2 class="text-lg font-medium text-gray-900">Jurunense</h2>
              <p class="text-sm text-gray-500">Home Center</p>
            </div>
          </div>
        </div>

        <!-- Navigation -->
        <nav class="flex-1 p-4 space-y-1">

          <!-- Admin Section -->
          <a
            href="/admin/security"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Consulta de Pedidos
          </a>

                    <a
            href="/buscar-pedido"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Comunicação interna
          </a>

          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Configurações
          </a>

          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            Ajuda & Suporte
          </a>
        </nav>

        <!-- User Profile -->
        <div class="p-4 border-t border-gray-200">
          <div class="flex items-center space-x-3">
            <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-medium">JC</span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-gray-900 truncate">JuruConnect</p>
              <p class="text-xs text-gray-500 truncate">Sistema Integrado</p>
            </div>
            <a
              href="/logout"
              class="p-1 text-red-600 hover:text-red-800 rounded-md hover:bg-red-50 text-sm font-medium transition-colors duration-200"
            >
              Sair
            </a>
            </div>
          </div>
        </div>

      <!-- Content Area - Apenas espaço em branco -->
      <div class="flex-1 ml-64 bg-gray-50">
        <%= live_render(@socket, AppWeb.DashboardResumoLive, id: :dashboard_resumo) %>
      </div>
    </div>
    """
  end
end
