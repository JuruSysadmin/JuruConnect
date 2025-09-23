defmodule App.Orders do
  @moduledoc """
  Busca pedidos na API externa do portal Jurunense.
  """

  @api_base_url "https://portalapi.jurunense.com/api/v1/orders/find?orderId="

  @doc """
  Busca um pedido específico pelo ID na API externa.
  Retorna os dados do pedido ou nil se não encontrado.
  """
  def get_order(order_id) when is_binary(order_id) do
    request_url = @api_base_url <> order_id

    case HTTPoison.get(request_url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => [order_data | _]}} -> order_data
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
