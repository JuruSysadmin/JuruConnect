defmodule AppWeb.DashboardNotificationPanel do
  use Phoenix.Component

  @doc """
  Renderiza o painel de notificações de celebração.
  Props:
    - notifications: lista de notificações
    - show_celebration: boolean
  """
  def notification_panel(assigns) do
    ~H"""
    <div class="fixed top-4 right-2 sm:right-4 z-40 space-y-2 w-80 sm:w-auto">
      <!-- Contador de Celebrações Ativas -->
      <%= if length(@notifications) > 0 do %>
        <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-2 rounded-full shadow-lg text-center animate-pulse">
          <span class="text-xs sm:text-sm font-medium">
            {length(@notifications)} Celebrações Globais Ativas
          </span>
        </div>
      <% end %>

      <!-- Notificações Individuais -->
      <%= for {notification, index} <- Enum.with_index(@notifications) do %>
        <div
          class="bg-gradient-to-r from-green-500 to-emerald-600 text-white p-3 sm:p-4 rounded-lg shadow-2xl max-w-sm bounce-in transform hover:scale-105 transition-all duration-300"
          style={"animation-delay: #{index * 0.1}s;"}
          id={"notification-#{notification.celebration_id}"}
        >
          <div class="flex items-center space-x-3">
            <div class="flex-shrink-0 relative">
              <div class="absolute -top-1 -right-1 w-3 h-3 bg-yellow-400 rounded-full animate-ping">
              </div>
            </div>
            <div class="flex-1">
              <h4 class="text-sm sm:text-base font-medium animate-bounce">
                Meta #{index + 1} Atingida!
                <span class="text-xs bg-white bg-opacity-20 px-2 py-1 rounded-full ml-2">
                  GLOBAL
                </span>
              </h4>
              <p class="text-xs sm:text-sm opacity-90 font-medium">{notification.store_name}</p>
              <p class="text-xs opacity-75">
                {AppWeb.DashboardUtils.format_money(notification.achieved)} ({if is_number(notification.percentage), do: :erlang.float_to_binary(notification.percentage * 1.0, decimals: 1), else: "0,0"}%)
              </p>
              <p class="text-xs opacity-60 mt-1 mobile-hide">
                ID: #{notification.celebration_id}
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
