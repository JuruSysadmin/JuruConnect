defmodule AppWeb.DashboardConfetti do
  @moduledoc """
  Componente para exibir alertas de celebração de metas atingidas.

  Renderiza alertas no topo central da tela com animações de fade-in
  quando metas são alcançadas.
  """

  use Phoenix.Component

  import AppWeb.DashboardUtils, only: [format_money: 1]

  @doc """
  Renderiza alertas de celebração usando componentes Alert do daisyUI.
  Exibe notificações com informações da loja e valor atingido.
  """
  def confetti(assigns) do
    ~H"""
    <%= if @show_celebration and @notifications != [] do %>
      <div class="fixed top-4 left-1/2 transform -translate-x-1/2 z-50 space-y-2 w-full max-w-md px-4">
        <%= for {notification, index} <- Enum.with_index(@notifications) do %>
          <div class="alert alert-success shadow-lg animate-fade-in" style={"animation-delay: #{index * 0.1}s;"}>
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div class="flex-1">
              <h3 class="font-bold text-sm">Parabéns! Meta Atingida! 🎉</h3>
              <div class="text-xs">
                <%= if Map.has_key?(notification, :store_name) do %>
                  <span class="font-semibold">{notification.store_name}</span>
                <% end %>
                <%= if Map.has_key?(notification, :achieved) do %>
                  <span class="ml-1">- {format_money(notification.achieved)}</span>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
