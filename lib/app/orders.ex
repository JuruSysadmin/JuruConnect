defmodule App.Orders do
  @moduledoc """
  Módulo responsável por buscar pedidos na API externa.
  """

  @api_url "https://portalapi.jurunense.com/api/v1/orders/find?orderId="

  @doc """
  Busca um pedido na API externa pelo ID.

  ## Parâmetros
    - `order_id`: ID do pedido (string)

  ## Retorna
    - `{:ok, pedido}` se encontrado
    - `{:error, :not_found}` se não encontrado
    - `{:error, :api_error}` se houver erro na API
    - `{:error, :invalid_response}` se a resposta for inválida

  ## Exemplo
      iex> get_order("12345")
      {:ok, %{"id" => "12345", "status" => "active", ...}}

      iex> get_order("inexistente")
      {:error, :not_found}
  """
  def get_order(order_id) when is_binary(order_id) and byte_size(order_id) > 0 do
    url = @api_url <> order_id

    case HTTPoison.get(url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_order_response(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, {:api_error, status_code}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp parse_order_response(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => [pedido | _]}} ->
        {:ok, pedido}

      {:ok, %{"data" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, _} ->
        {:error, :invalid_response}
    end
  end

  @doc """
  Cria um via tuple para o Registry do chat.

  ## Parâmetros
    - `order_id`: ID do pedido (string)

  ## Retorna
    - Via tuple para o Registry

  ## Exemplo
      iex> via_tuple("12345")
      {:via, Registry, {App.ChatRegistry, "12345"}}
  """
  def via_tuple(order_id) when is_binary(order_id),
    do: {:via, Registry, {App.ChatRegistry, order_id}}

  @doc """
  Busca o PID de uma sala de chat pelo ID do pedido.

  ## Parâmetros
    - `order_id`: ID do pedido (string)

  ## Retorna
    - `{:ok, pid}` se a sala existir
    - `{:error, :not_found}` se a sala não existir

  ## Exemplo
      iex> lookup_room("12345")
      {:ok, #PID<0.123.0>}

      iex> lookup_room("inexistente")
      {:error, :not_found}
  """
  def lookup_room(order_id) when is_binary(order_id) do
    case Registry.lookup(App.ChatRegistry, order_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
