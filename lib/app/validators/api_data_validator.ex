defmodule App.Validators.ApiDataValidator do
  @moduledoc """
  Validador para dados vindos da API externa.
  Garante integridade e segurança dos dados antes do processamento.
  """

  def validate_sale_data(data) when is_map(data) do
    errors = []

    errors = if get_value(data, :seller_name) == nil or get_value(data, "seller_name") == nil do
      [{:seller_name, "is required"} | errors]
    else
      errors
    end

    errors = if get_value(data, :store) == nil or get_value(data, "store") == nil do
      [{:store, "is required"} | errors]
    else
      errors
    end

    errors = if get_value(data, :sale_value) == nil or get_value(data, "sale_value") == nil do
      [{:sale_value, "is required"} | errors]
    else
      errors
    end

    errors = if get_value(data, :timestamp) == nil or get_value(data, "timestamp") == nil do
      [{:timestamp, "is required"} | errors]
    else
      errors
    end

    if errors == [] do
      {:ok, data}
    else
      {:error, errors}
    end
  end

  def validate_sale_data(_), do: {:error, "Invalid data format"}

  defp get_value(data, key) when is_atom(key) do
    Map.get(data, key) || Map.get(data, to_string(key))
  end

  defp get_value(data, key) when is_binary(key) do
    Map.get(data, key) || Map.get(data, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(data, key)
  end

  def sanitize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[<>\"'&]/, "")
    |> String.slice(0, 255)
  end

  def sanitize_string(value), do: value

  def validate_dashboard_data(data) when is_map(data) do
    if Map.has_key?(data, "companies") or Map.has_key?(data, :companies) do
      {:ok, data}
    else
      {:error, "Invalid dashboard data structure"}
    end
  end

  def validate_dashboard_data(_), do: {:error, "Invalid dashboard data format"}
end
