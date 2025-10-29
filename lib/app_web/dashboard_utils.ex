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
  Formata um valor de peso em toneladas.
  O valor já vem em toneladas da API, apenas formata sem converter.
  """
  @spec format_weight_in_tons(float | integer | binary | any) :: String.t()
  def format_weight_in_tons(value) when is_float(value) or is_integer(value) do
    format_tons_only(value)
  end

  @spec format_weight_in_tons(binary) :: String.t()
  def format_weight_in_tons(value) when is_binary(value) do
    clean_value = value |> String.replace(".", "") |> String.replace(",", ".")

    case Float.parse(clean_value) do
      {num, _} -> format_tons_only(num)
      :error -> "0"
    end
  end

  @spec format_weight_in_tons(any) :: String.t()
  def format_weight_in_tons(_), do: "0"

  defp format_tons_only(value) when is_float(value) or is_integer(value) do
    formatted =
      if value == trunc(value) do
        value |> trunc() |> Integer.to_string()
      else
        value |> :erlang.float_to_binary(decimals: 2) |> String.replace(".", ",")
      end

    if String.contains?(formatted, ",") do
      [int, frac] = String.split(formatted, ",")
      int = add_thousands_separator_to_int(int)
      int <> "," <> frac
    else
      add_thousands_separator_to_int(formatted)
    end
  end

  defp format_tons_only(_), do: "0"

  defp add_thousands_separator_to_int(int_str) do
    int_str
    |> String.reverse()
    |> String.replace(~r/(...)(?=.)/, "\\1.")
    |> String.reverse()
  end

  @spec add_thousands_separator(String.t()) :: String.t()
  def add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = add_thousands_separator_to_int(int)
    int <> "," <> frac
  end

  @spec calculate_percentual_number(map) :: float
  def calculate_percentual_number(data) when is_map(data) do
    case Map.get(data, :percentual, 0.0) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) -> parse_percent_string(value)
      _ -> 0.0
    end
  end

  defp parse_percent_string(value) do
    cleaned_value =
      value
      |> String.replace(",", ".")
      |> String.replace("%", "")
      |> String.trim()

    case cleaned_value do
      "" -> 0.0
      clean -> parse_to_float(clean)
    end
  end

  defp parse_to_float(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> 0.0
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
        date_time
        |> DateTime.to_date()
        |> Date.day_of_week()
        |> weekday_to_portuguese()
      {:error, _} ->
        "Data inválida"
    end
  end

  def get_weekday(_), do: "Data inválida"

  defp weekday_to_portuguese(1), do: "Segunda-feira"
  defp weekday_to_portuguese(2), do: "Terça-feira"
  defp weekday_to_portuguese(3), do: "Quarta-feira"
  defp weekday_to_portuguese(4), do: "Quinta-feira"
  defp weekday_to_portuguese(5), do: "Sexta-feira"
  defp weekday_to_portuguese(6), do: "Sábado"
  defp weekday_to_portuguese(7), do: "Domingo"
  defp weekday_to_portuguese(_), do: "Data inválida"
end
