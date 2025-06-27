defmodule AppWeb.DashboardUtils do
  @moduledoc """
  Utilidades compartilhadas para formatação de dados do dashboard
  """

  @doc """
  Formata um valor numérico como moeda brasileira
  """
  def format_money(value) when is_number(value) do
    value = value * 1.0
    "R$\u00A0" <>
      (value
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")
      |> add_thousands_separator())
  end

  def format_money(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_money(num)
      :error -> "R$ 0,00"
    end
  end

  def format_money(_), do: "R$ 0,00"

  @doc """
  Formata um valor numérico como percentual
  """
  def format_percent(value) when is_number(value) do
    value = value * 1.0
    value
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>("%")
  end

  def format_percent(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_percent(num)
      :error -> "0,00%"
    end
  end

  def format_percent(_), do: "0,00%"

  @doc """
  Adiciona separador de milhares no formato brasileiro
  """
  def add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = int |> String.reverse() |> String.replace(~r/(...)(?=.)/, "\\1.") |> String.reverse()
    int <> "," <> frac
  end

  @doc """
  Converte percentual string para número, tratando vírgula decimal e símbolo %
  """
  def parse_percent_to_number(value) when is_binary(value) do
    value
    |> String.replace(",", ".")
    |> String.replace("%", "")
    |> String.trim()
    |> case do
      "" -> 0.0
      clean_value ->
        case Float.parse(clean_value) do
          {num, _} -> num
          :error -> 0.0
        end
    end
  end

  def parse_percent_to_number(value) when is_number(value), do: value * 1.0
  def parse_percent_to_number(_), do: 0.0

  @doc """
  Calcula margem de lucro
  """
  def calculate_margin(data) do
    sale = get_numeric_value(data, "sale")
    discount = get_numeric_value(data, "discount")

    if sale > 0 do
      ((sale - discount) / sale) * 100
    else
      0.0
    end
  end

  @doc """
  Calcula ticket médio
  """
  def calculate_ticket(data) do
    sale = get_numeric_value(data, "sale")
    nfs = get_numeric_value(data, "nfs")

    if nfs > 0 do
      sale / nfs
    else
      0.0
    end
  end

  @doc """
  Extrai valor numérico de um mapa, com fallback para 0
  """
  def get_numeric_value(data, key) when is_map(data) do
    case Map.get(data, key, 0) do
      value when is_number(value) -> value * 1.0
      value when is_binary(value) ->
        case Float.parse(value) do
          {num, _} -> num
          :error -> 0.0
        end
      _ -> 0.0
    end
  end

  def get_numeric_value(_, _), do: 0.0
end
