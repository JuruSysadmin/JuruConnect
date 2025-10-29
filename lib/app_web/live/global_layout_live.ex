defmodule AppWeb.GlobalLayoutLive do
  use AppWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:devolucao")
    end
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:devolucao_aumentou, %{devolution: val, diff: diff, sellerName: seller}}, socket) do
    msg = "Atenção: Nova devolução registrada para #{seller}! Valor: R$ #{AppWeb.DashboardUtils.format_money(val)} (aumento de R$ #{AppWeb.DashboardUtils.format_money(diff)})"
    {:noreply, put_flash(socket, :error, msg)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= if @flash[:error] do %>
      <div id="global-flash-error" phx-hook="AutoHideFlash" class="fixed top-4 left-1/2 transform -translate-x-1/2 z-50 w-full max-w-md px-4">
        <div class="bg-red-100 border border-red-300 text-red-800 px-4 py-3 rounded-lg shadow-lg flex items-center space-x-2 animate-fade-in">
          <svg class="w-5 h-5 text-red-500 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 5.636l-1.414-1.414A9 9 0 105.636 18.364l1.414 1.414A9 9 0 1018.364 5.636z" />
          </svg>
          <span class="font-semibold"><%= @flash[:error] %></span>
        </div>
      </div>
    <% end %>
    <%= @inner_content %>
    """
  end
end
