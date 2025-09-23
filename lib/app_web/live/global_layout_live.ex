defmodule AppWeb.GlobalLayoutLive do
  @moduledoc """
  LiveView para o layout global da aplicação.

  Este módulo gerencia o layout global e notificações de devoluções
  que são exibidas em toda a aplicação.
  """

  use AppWeb, :live_view

  @impl true
  @spec mount(map, map, Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket = case connected?(socket) do
      true ->
        Phoenix.PubSub.subscribe(App.PubSub, "dashboard:devolucao")
        socket
      false ->
        socket
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_info(tuple, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:devolucao_aumentou, %{devolution: val, diff: diff, sellerName: seller}}, socket) do
    message = build_devolution_message(seller, val, diff)
    {:noreply, put_flash(socket, :error, message)}
  end

  @doc """
  Constrói a mensagem de notificação para devoluções.
  """
  @spec build_devolution_message(String.t(), number(), number()) :: String.t()
  defp build_devolution_message(seller, val, diff) do
    formatted_val = AppWeb.DashboardUtils.format_money(val)
    formatted_diff = AppWeb.DashboardUtils.format_money(diff)

    "Atenção: Nova devolução registrada para #{seller}! Valor: R$ #{formatted_val} (aumento de R$ #{formatted_diff})"
  end

  @impl true
  @spec render(map) :: Phoenix.LiveView.Rendered.t()
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
