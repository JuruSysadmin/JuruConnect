defmodule AppWeb.SalesFeedComponent do
  @moduledoc """
  Componente minimalista para exibição do feed de vendas.

  Exibe uma lista simples e limpa das vendas recentes com informações essenciais:
  vendedor, valor, loja e horário.
  """

  use AppWeb, :live_component

  @doc """
  Monta o componente com configurações iniciais minimalistas.
  """
  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign_initial_data()

    {:ok, socket}
  end

  @doc """
  Atualiza o componente quando recebe novos dados.
  """
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_display_feed()

    {:ok, socket}
  end

  @doc """
  Não há eventos para processar no modo minimalista.
  """
  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  # Funções privadas

  defp assign_initial_data(socket) do
    assign(socket,
      sales_feed: [],
      display_feed: []
    )
  end

  defp assign_display_feed(socket) do
    feed = socket.assigns.sales_feed || []

    # Limita a 10 vendas mais recentes para manter minimalista
    display_feed =
      feed
      |> Enum.take(10)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    assign(socket, display_feed: display_feed)
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "agora"
      diff < 3600 -> "#{Kernel.div(diff, 60)}m"
      diff < 86_400 -> "#{Kernel.div(diff, 3600)}h"
      true -> Calendar.strftime(datetime, "%d/%m")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-100 p-4">
      <!-- Header simples -->
      <div class="mb-4">
        <h2 class="text-base font-medium text-gray-900">Vendas Recentes</h2>
        <p class="text-xs text-gray-500 mt-1">Últimas <%= length(@display_feed) %> vendas</p>
      </div>

      <!-- Lista minimalista de vendas -->
      <div class="space-y-2 max-h-80 overflow-y-auto">
        <%= if Enum.empty?(@display_feed) do %>
          <div class="text-center py-8">
            <div class="text-gray-400 text-sm">Nenhuma venda registrada</div>
          </div>
        <% else %>
          <%= for sale <- @display_feed do %>
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors">
              <!-- Informações da venda -->
              <div class="flex-1">
                <div class="flex items-center space-x-3">
                  <div class="flex-1">
                    <div class="font-medium text-gray-900 text-sm"><%= sale.seller_name %></div>
                    <div class="text-xs text-gray-500"><%= sale.store %></div>
                  </div>

                  <div class="text-right">
                    <div class="font-mono text-green-600 text-sm"><%= sale.sale_value_formatted %></div>
                    <div class="text-xs text-gray-400"><%= time_ago(sale.timestamp) %></div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
