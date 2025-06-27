defmodule App.Orders do
  @moduledoc """
  Módulo responsável por buscar pedidos na API externa.
  """

  @api_url "https://portalapi.jurunense.com/api/v1/orders/find?orderId="

  def get_order(order_id) when is_binary(order_id) do
    url = @api_url <> order_id

    case HTTPoison.get(url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, %{"data" => [pedido | _]}} <- Jason.decode(body) do
          pedido
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def via_tuple(order_id), do: {:via, Registry, {App.ChatRegistry, order_id}}

  def lookup_room(order_id) do
    case Registry.lookup(App.ChatRegistry, order_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
