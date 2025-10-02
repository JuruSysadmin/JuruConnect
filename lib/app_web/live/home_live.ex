defmodule AppWeb.HomeLive do
  use AppWeb, :live_view

  on_mount {AppWeb.UserAuth, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="py-6">
            <h1 class="text-3xl font-bold text-gray-900">Dashboard</h1>
            <p class="mt-1 text-sm text-gray-600">Bem-vindo ao JuruConnect</p>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="bg-white rounded-lg shadow p-8">
          <div class="text-center">
            <div class="mx-auto h-20 w-20 text-gray-400">
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1">
                <path stroke-linecap="round" stroke-linejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h2 class="mt-6 text-2xl font-bold text-gray-900">JuruConnect</h2>
            <p class="mt-2 text-gray-600">Sistema de gerenciamento e comunicação</p>
          </div>

          <div class="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <div class="px-4 py-5 bg-blue-50 rounded-lg">
              <dt class="text-lg font-medium text-blue-900">Tratativas Ativas</dt>
              <dd class="mt-1 text-3xl font-semibold text-blue-600">Sistema de Comunicação</dd>
            </div>

            <div class="px-4 py-5 bg-green-50 rounded-lg">
              <dt class="text-lg font-medium text-green-900">Status Geral</dt>
              <dd class="mt-1 text-3xl font-semibold text-green-600">Operacional</dd>
            </div>

            <div class="px-4 py-5 bg-purple-50 rounded-lg">
              <dt class="text-lg font-medium text-purple-900">Usuários Conectados</dt>
              <dd class="mt-1 text-3xl font-semibold text-purple-600">Online</dd>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
