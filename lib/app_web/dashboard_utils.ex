defmodule AppWeb.DashboardUtils do
  @moduledoc """
  Utilidades compartilhadas para formatação de dados do dashboard
  """

  @spec format_money(float | integer | binary | any) :: String.t()
  def format_money(value) when is_float(value) do
    "R$\u00A0" <>
      (value
       |> :erlang.float_to_binary(decimals: 2)
       |> String.replace(".", ",")
       |> add_thousands_separator())
  end

  @spec format_money(integer) :: String.t()
  def format_money(value) when is_integer(value) do
    format_money(value * 1.0)
  end

  @spec format_money(binary) :: String.t()
  def format_money(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_money(num)
      :error -> "R$ 0,00"
    end
  end

  @spec format_money(any) :: String.t()
  def format_money(_), do: "R$ 0,00"

  @spec format_percent(float | integer | binary | any) :: String.t()
  def format_percent(value) when is_float(value) do
    value
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>("%")
  end

  @spec format_percent(integer) :: String.t()
  def format_percent(value) when is_integer(value) do
    format_percent(value * 1.0)
  end

  @spec format_percent(binary) :: String.t()
  def format_percent(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_percent(num)
      :error -> "0,00%"
    end
  end

  @spec format_percent(any) :: String.t()
  def format_percent(_), do: "0,00%"

  @spec add_thousands_separator(String.t()) :: String.t()
  def add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = int |> String.reverse() |> String.replace(~r/(...)(?=.)/, "\\1.") |> String.reverse()
    int <> "," <> frac
  end

  @spec parse_percent_to_number(binary | float | integer | nil | any) :: float
  def parse_percent_to_number(value) when is_binary(value) do
    value
    |> String.replace(",", ".")
    |> String.replace("%", "")
    |> String.trim()
    |> case do
      "" ->
        0.0
      clean_value ->
        case Float.parse(clean_value) do
          {num, _} -> num
          :error -> 0.0
        end
    end
  end

  @spec parse_percent_to_number(float) :: float
  def parse_percent_to_number(value) when is_float(value), do: value

  @spec parse_percent_to_number(integer) :: float
  def parse_percent_to_number(value) when is_integer(value), do: value * 1.0

  @spec parse_percent_to_number(nil) :: float
  def parse_percent_to_number(nil), do: 0.0

  @spec parse_percent_to_number(any) :: float
  def parse_percent_to_number(_), do: 0.0

  @spec calculate_margin(map) :: float
  def calculate_margin(data) do
    sale = get_numeric_value(data, "sale")
    discount = get_numeric_value(data, "discount")

    if sale > 0 do
      (sale - discount) / sale * 100
    else
      0.0
    end
  end

  @spec calculate_ticket(map) :: float
  def calculate_ticket(data) do
    sale = get_numeric_value(data, "sale")
    nfs = get_numeric_value(data, "nfs")

    if nfs > 0 do
      sale / nfs
    else
      0.0
    end
  end

  @spec get_numeric_value(map, String.t()) :: float
  def get_numeric_value(data, key) when is_map(data) do
    case Map.get(data, key, 0) do
      value when is_float(value) ->
        value
      value when is_integer(value) ->
        value * 1.0
      value when is_binary(value) ->
        case Float.parse(value) do
          {num, _} -> num
          :error -> 0.0
        end
      _ ->
        0.0
    end
  end

  @spec get_numeric_value(any, any) :: float
  def get_numeric_value(_, _), do: 0.0

  @spec calculate_percentual_number(map) :: float
  def calculate_percentual_number(data) when is_map(data) do
    case Map.get(data, :percentual, 0.0) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) -> parse_percent_to_number(value)
      _ -> 0.0
    end
  end
end
