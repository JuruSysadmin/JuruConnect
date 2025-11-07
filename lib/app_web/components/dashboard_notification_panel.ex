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
        <div role="alert" class="alert alert-info shadow-lg animate-pulse">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-5 w-5" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span class="text-xs sm:text-sm font-medium">
            Parabéns!
          </span>
        </div>
      <% end %>

      <%= for {notification, index} <- Enum.with_index(@notifications) do %>
        <div
          role="alert"
          class="alert alert-success shadow-2xl max-w-sm animate-fade-in transform hover:scale-105 transition-all duration-300"
          style={"animation-delay: #{index * 0.1}s;"}
          id={"notification-#{notification.celebration_id}"}
        >
          <div class="flex-shrink-0 relative">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div class="absolute -top-1 -right-1 w-3 h-3 bg-warning rounded-full animate-ping"></div>
          </div>
          <div class="flex-1">
            <h4 class="text-sm sm:text-base font-bold animate-bounce">
              {get_goal_title(notification)}
              {raw(badge_element(notification))}
            </h4>
            <%= if seller_goal?(notification) do %>
              <p class="text-xs sm:text-sm opacity-90 font-medium">Vendedor: {notification.store_name}</p>
            <% else %>
              <p class="text-xs sm:text-sm opacity-90 font-medium">Loja: {notification.store_name}</p>
            <% end %>
            <p class="text-xs opacity-75">
              {AppWeb.DashboardUtils.format_money(notification.achieved)} ({format_percentage(notification.percentage)}%)
            </p>
            <p class="text-xs opacity-60 mt-1 mobile-hide">
              ID: #{notification.celebration_id}
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp badge_element(notification) do
    render_badge(get_badge_type(notification))
  end

  defp render_badge({:daily, label}),
    do: ~s(<span class="badge badge-success badge-sm ml-2">#{label}</span>)

  defp render_badge({:monthly, label}),
    do: ~s(<span class="badge badge-secondary badge-sm ml-2">#{label}</span>)

  defp render_badge({:real, label}),
    do: ~s(<span class="badge badge-primary badge-sm ml-2">#{label}</span>)

  defp render_badge({:global, label}),
    do: ~s(<span class="badge badge-neutral badge-sm ml-2">#{label}</span>)

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

  defp seller_goal?(%{type: :seller_daily_goal}), do: true
  defp seller_goal?(%{supervisor_id: id}) when not is_nil(id), do: true
  defp seller_goal?(_), do: false

  defp format_percentage(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
  defp format_percentage(_), do: "0,0"

  defp get_goal_title(%{type: :seller_daily_goal}), do: "Meta do Vendedor Atingida!"
  defp get_goal_title(%{supervisor_id: id}) when not is_nil(id), do: "Meta do Vendedor Atingida!"
  defp get_goal_title(%{type: :daily_goal}), do: "Meta Diária Atingida!"
  defp get_goal_title(%{target: target}) when target >= 100_000, do: "Meta Mensal Atingida!"
  defp get_goal_title(%{type: :hourly_goal}), do: "Meta Horária Atingida!"
  defp get_goal_title(%{type: :exceptional_performance}), do: "Performance Excepcional!"
  defp get_goal_title(%{type: :top_seller}), do: "Vendedor Destaque!"
  defp get_goal_title(%{type: :monthly_milestone}), do: "Marco Mensal Alcançado!"
  defp get_goal_title(_), do: "Meta Atingida!"
end
