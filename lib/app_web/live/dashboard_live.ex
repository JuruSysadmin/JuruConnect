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
    <div class="flex flex-col min-h-screen bg-gray-50">
      <div class="flex-1 bg-gray-50">
        <%= live_render(@socket, AppWeb.DashboardResumoLive, id: :dashboard_resumo) %>
      </div>
    </div>
    """
  end
end
