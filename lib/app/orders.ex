defmodule App.Orders do
  @moduledoc """
  Order management context for external API integration and chat room coordination.

  Provides functions for fetching order data from external APIs and managing
  chat room associations. Handles API communication, data parsing, and
  registry-based room lookup for real-time chat functionality.
  """

  @api_url "https://portalapi.jurunense.com/api/v1/orders/find?orderId="

  @doc """
  Fetches order data from external API by order ID.

  Retrieves order information from the external portal API, handling
  network timeouts and parsing the JSON response. Returns the first
  order from the API response or nil if not found or on error.
  """
  def get_order(order_id) when is_binary(order_id) do
    order_id
    |> build_api_url()
    |> fetch_order_from_api()
    |> parse_order_response()
  end

  @doc """
  Creates a via tuple for GenServer registration in the chat registry.

  Enables dynamic process registration for order-specific chat rooms,
  allowing multiple processes to be associated with the same order ID.
  """
  def via_tuple(order_id), do: {:via, Registry, {App.ChatRegistry, order_id}}

  @doc """
  Looks up the chat room process for a specific order.

  Searches the chat registry for an active process associated with the order ID.
  Returns the process PID if found, or nil if no active chat room exists.
  """
  def lookup_room(order_id) do
    case Registry.lookup(App.ChatRegistry, order_id) do
      [{process_pid, _}] -> process_pid
      [] -> nil
    end
  end

  # Builds the complete API URL for order lookup
  defp build_api_url(order_id) do
    @api_url <> order_id
  end

  # Fetches order data from the external API with timeout
  defp fetch_order_from_api(api_url) do
    case HTTPoison.get(api_url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, response_body}
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, :api_error, status_code}
      {:error, reason} ->
        {:error, :network_error, reason}
    end
  end

  # Parses the JSON response and extracts the first order
  defp parse_order_response({:ok, response_body}) do
    case Jason.decode(response_body) do
      {:ok, %{"data" => [first_order | _]}} ->
        {:ok, first_order}
      {:ok, %{"data" => []}} ->
        {:error, :order_not_found}
      {:ok, _} ->
        {:error, :invalid_response_format}
      {:error, reason} ->
        {:error, :json_parse_error, reason}
    end
  end
  defp parse_order_response({:error, error_type, details}) do
    {:error, error_type, details}
  end
end
