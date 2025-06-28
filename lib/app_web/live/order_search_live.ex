defmodule AppWeb.OrderSearchLive do
  use AppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, order_id: "", error: nil)}
  end

  def handle_event("search", %{"order_id" => order_id}, socket) do
    case App.Orders.get_order(order_id) do
      nil ->
        {:noreply, assign(socket, error: "Pedido não encontrado", order_id: order_id)}

      _order ->
        {:noreply, push_navigate(socket, to: "/chat/#{order_id}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen bg-gray-50">
      <div class="bg-white p-8 rounded shadow w-full max-w-md">
        <h2 class="text-2xl font-bold mb-4 text-center">Buscar Pedido</h2>
        <form phx-submit="search" class="flex flex-col gap-4">
          <input
            name="order_id"
            value={@order_id}
            placeholder="Digite o número do pedido"
            class="border rounded px-3 py-2"
          />
          <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded">Buscar</button>
        </form>
        <%= if @error do %>
          <p class="text-red-600 mt-4 text-center">{@error}</p>
        <% end %>
      </div>
    </div>
    """
  end
end
