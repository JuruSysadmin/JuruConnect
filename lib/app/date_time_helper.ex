defmodule App.DateTimeHelper do
  @moduledoc """
  Helper para gerenciar datas e horários no timezone de São Paulo, Brasil.
  """

  @doc """
  Retorna a data e hora atual no timezone de São Paulo.
  """
  def now do
    Timex.now("America/Sao_Paulo")
  end

  @doc """
  Converte uma data UTC para o timezone de São Paulo.
  """
  def to_sao_paulo_timezone(datetime) when is_struct(datetime, DateTime) do
    Timex.to_datetime(datetime, "America/Sao_Paulo")
  end

  @doc """
  Converte uma string ISO8601 para o timezone de São Paulo.
  """
  def parse_and_convert_to_sao_paulo(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _} -> to_sao_paulo_timezone(datetime)
      _ -> nil
    end
  end

  @doc """
  Formata uma data para exibição no formato brasileiro (DD/MM/YYYY).
  """
  def format_date_br(datetime) do
    case to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt ->
        "#{String.pad_leading("#{dt.day}", 2, "0")}/#{String.pad_leading("#{dt.month}", 2, "0")}/#{dt.year}"
      _ ->
        "Data não disponível"
    end
  end

  @doc """
  Formata uma hora para exibição no formato brasileiro (HH:MM).
  """
  def format_time_br(datetime) do
    case to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt ->
        "#{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}"
      _ ->
        "Hora não disponível"
    end
  end

  @doc """
  Formata uma data e hora para exibição no formato brasileiro (DD/MM/YYYY HH:MM).
  """
  def format_datetime_br(datetime) do
    case to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt ->
        "#{format_date_br(dt)} #{format_time_br(dt)}"
      _ ->
        "Data/hora não disponível"
    end
  end

  @doc """
  Formata uma data relativa (ex: "há 2 horas", "ontem", etc.).
  """
  def format_relative_time_br(datetime) do
    case to_sao_paulo_timezone(datetime) do
      %DateTime{} = dt -> format_relative_time_for_datetime(dt)
      _ -> "Data não disponível"
    end
  end

  defp format_relative_time_for_datetime(dt) do
    now = now()
    diff_seconds = Timex.diff(now, dt, :second)
    format_time_difference(diff_seconds, dt)
  end

  defp format_time_difference(diff_seconds, dt) do
    case get_time_unit(diff_seconds) do
      :now -> "agora"
      :minutes -> format_minutes_ago(diff_seconds)
      :hours -> format_hours_ago(diff_seconds)
      :days -> format_days_ago(diff_seconds)
      :date -> format_date_br(dt)
    end
  end

  defp get_time_unit(diff_seconds) do
    cond do
      diff_seconds < 60 -> :now
      diff_seconds < 3600 -> :minutes
      diff_seconds < 86_400 -> :hours
      diff_seconds < 2_592_000 -> :days
      true -> :date
    end
  end

  defp format_minutes_ago(diff_seconds) do
    minutes = div(diff_seconds, 60)
    "#{minutes} #{pluralize_minutes(minutes)} atrás"
  end

  defp format_hours_ago(diff_seconds) do
    hours = div(diff_seconds, 3600)
    "#{hours} #{pluralize_hours(hours)} atrás"
  end

  defp format_days_ago(diff_seconds) do
    days = div(diff_seconds, 86_400)
    "#{days} #{pluralize_days(days)} atrás"
  end

  defp pluralize_minutes(1), do: "minuto"
  defp pluralize_minutes(_), do: "minutos"

  defp pluralize_hours(1), do: "hora"
  defp pluralize_hours(_), do: "horas"

  defp pluralize_days(1), do: "dia"
  defp pluralize_days(_), do: "dias"

  @doc """
  Converte uma string de data para o timezone de São Paulo.
  """
  def parse_date_string(date_string) when is_binary(date_string) and date_string != "" do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> to_sao_paulo_timezone(datetime)
      _ -> nil
    end
  end

  @doc """
  Retorna o nome do timezone atual configurado.
  """
  def current_timezone do
    "America/Sao_Paulo"
  end
end
