defmodule AppWeb.DashboardNotificationPanel do
  @moduledoc """
  Componente para exibir notificações de celebração de metas no dashboard.

  Renderiza um painel fixo no canto superior direito com notificações
  de conquistas de metas diárias, mensais e de vendedores.
  """

  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Renderiza o painel de notificações com contador de celebrações ativas
  e lista de notificações individuais com animações.
  """
  def notification_panel(assigns) do
    ~H"""
    <div class="fixed top-4 right-2 sm:right-4 z-40 space-y-2 w-80 sm:w-auto">
      <%= if @notifications != [] do %>
        <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-2 rounded-full shadow-lg text-center animate-pulse">
          <span class="text-xs sm:text-sm font-medium">
            Parabéns!
          </span>
        </div>
      <% end %>

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
                {get_goal_title(notification)}
                {raw(badge_element(notification))}
              </h4>
              <%= if is_seller_goal?(notification) do %>
                <p class="text-xs sm:text-sm opacity-90 font-medium">Vendedor: {notification.store_name}</p>
              <% else %>
                <p class="text-xs sm:text-sm opacity-90 font-medium"> Loja: {notification.store_name}</p>
              <% end %>
              <p class="text-xs opacity-75">
                {AppWeb.DashboardUtils.format_money(notification.achieved)} ({format_percentage(notification.percentage)}%)
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

  defp badge_element(notification) do
    case get_badge_type(notification) do
      {:daily, label} ->
        ~s(<span class="text-xs bg-green-400 bg-opacity-30 px-2 py-1 rounded-full ml-2"> #{label}</span>)
      {:monthly, label} ->
        ~s(<span class="text-xs bg-purple-400 bg-opacity-30 px-2 py-1 rounded-full ml-2"> #{label}</span>)
      {:real, label} ->
        ~s(<span class="text-xs bg-blue-400 bg-opacity-30 px-2 py-1 rounded-full ml-2"> #{label}</span>)
      {:global, label} ->
        ~s(<span class="text-xs bg-white bg-opacity-20 px-2 py-1 rounded-full ml-2"> #{label}</span>)
    end
  end

  defp get_badge_type(%{type: "real", level: level}), do: {:real, get_level_label(level)}
  defp get_badge_type(%{type: "real"}), do: {:real, "CONQUISTA"}
  defp get_badge_type(%{target: target}) when target >= 100_000, do: {:monthly, "META MENSAL"}
  defp get_badge_type(%{target: target}) when target >= 10_000, do: {:daily, "META DIÁRIA"}
  defp get_badge_type(%{target: _target}), do: {:daily, "PEQUENA META"}
  defp get_badge_type(_), do: {:global, "CONQUISTA"}

  defp get_level_label("bronze"), do: "BRONZE"
  defp get_level_label("silver"), do: "PRATA"
  defp get_level_label("gold"), do: "OURO"
  defp get_level_label("platinum"), do: "PLATINA"
  defp get_level_label(_), do: "CONQUISTA"

  defp is_seller_goal?(%{type: :seller_daily_goal}), do: true
  defp is_seller_goal?(%{supervisor_id: id}) when not is_nil(id), do: true
  defp is_seller_goal?(_), do: false

  defp format_percentage(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
  defp format_percentage(_), do: "0,0"

  defp get_goal_title(notification) do
    cond do
      is_seller_goal?(notification) ->
        "Meta do Vendedor Atingida!"

      Map.has_key?(notification, :type) and notification.type == :daily_goal ->
        "Meta Diária Atingida!"

      Map.has_key?(notification, :target) and notification.target >= 100_000 ->
        "Meta Mensal Atingida!"

      Map.has_key?(notification, :type) and notification.type == :hourly_goal ->
        "Meta Horária Atingida!"

      Map.has_key?(notification, :type) and notification.type == :exceptional_performance ->
        "Performance Excepcional!"

      Map.has_key?(notification, :type) and notification.type == :top_seller ->
        "Vendedor Destaque!"

      Map.has_key?(notification, :type) and notification.type == :monthly_milestone ->
        "Marco Mensal Alcançado!"

      true ->
        "Meta Atingida!"
    end
  end
end
