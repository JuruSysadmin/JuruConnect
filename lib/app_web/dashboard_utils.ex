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

  @doc """
  Formata um valor de peso em kg.
  """
  @spec format_weight(float | integer | binary | any) :: String.t()
  def format_weight(value) when is_float(value) do
    value
    |> :erlang.float_to_binary(decimals: 3)
    |> String.replace(".", ",")
  end

  @spec format_weight(integer) :: String.t()
  def format_weight(value) when is_integer(value) do
    format_weight(value * 1.0)
  end

  @spec format_weight(binary) :: String.t()
  def format_weight(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_weight(num)
      :error -> "0,000"
    end
  end

  @spec format_weight(any) :: String.t()
  def format_weight(_), do: "0,000"

  @doc """
  Formata peso retornando valor formatado e unidade (kg ou ton).
  Converte valores >= 1000 kg para toneladas.
  """
  @spec format_weight_with_unit(float | integer | binary | any) :: {String.t(), String.t()}
  def format_weight_with_unit(value) when is_float(value) do
    cond do
      value >= 1000 ->
        tons = value / 1000
        formatted = tons
          |> :erlang.float_to_binary(decimals: 3)
          |> String.replace(".", ",")
        {formatted, "ton"}
      true ->
        formatted = value
          |> :erlang.float_to_binary(decimals: 3)
          |> String.replace(".", ",")
        {formatted, "kg"}
    end
  end

  @spec format_weight_with_unit(integer) :: {String.t(), String.t()}
  def format_weight_with_unit(value) when is_integer(value) do
    format_weight_with_unit(value * 1.0)
  end

  @spec format_weight_with_unit(binary) :: {String.t(), String.t()}
  def format_weight_with_unit(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_weight_with_unit(num)
      :error -> {"0,000", "kg"}
    end
  end

  @spec format_weight_with_unit(any) :: {String.t(), String.t()}
  def format_weight_with_unit(_), do: {"0,000", "kg"}

  @spec add_thousands_separator(String.t()) :: String.t()
  def add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = int |> String.reverse() |> String.replace(~r/(...)(?=.)/, "\\1.") |> String.reverse()
    int <> "," <> frac
  end

  @spec calculate_percentual_number(map) :: float
  def calculate_percentual_number(data) when is_map(data) do
    case Map.get(data, :percentual, 0.0) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) ->
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
      _ -> 0.0
    end
  end

  @doc """
  Formata uma data ISO para o formato brasileiro (DD/MM/YYYY).
  """
  @spec format_date(String.t()) :: String.t()
  def format_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, date_time, _offset} ->
        date = DateTime.to_date(date_time)
        Calendar.strftime(date, "%d/%m/%Y")
      {:error, _} ->
        "Data inválida"
    end
  end

  def format_date(_), do: "Data inválida"

  @doc """
  Retorna o dia da semana em português.
  """
  @spec get_weekday(String.t()) :: String.t()
  def get_weekday(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, date_time, _offset} ->
        date = DateTime.to_date(date_time)
        case Date.day_of_week(date) do
          1 -> "Segunda-feira"
          2 -> "Terça-feira"
          3 -> "Quarta-feira"
          4 -> "Quinta-feira"
          5 -> "Sexta-feira"
          6 -> "Sábado"
          7 -> "Domingo"
        end
      {:error, _} ->
        "Data inválida"
    end
  end

  def get_weekday(_), do: "Data inválida"
end
