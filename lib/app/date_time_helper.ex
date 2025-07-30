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
      %DateTime{} = dt ->
        now = now()
        diff_seconds = Timex.diff(now, dt, :second)

        cond do
          diff_seconds < 60 ->
            "agora"
          diff_seconds < 3600 ->
            minutes = div(diff_seconds, 60)
            "#{minutes} #{if minutes == 1, do: "minuto", else: "minutos"} atrás"
          diff_seconds < 86400 ->
            hours = div(diff_seconds, 3600)
            "#{hours} #{if hours == 1, do: "hora", else: "horas"} atrás"
          diff_seconds < 2592000 ->
            days = div(diff_seconds, 86400)
            "#{days} #{if days == 1, do: "dia", else: "dias"} atrás"
          true ->
            format_date_br(dt)
        end
      _ ->
        "Data não disponível"
    end
  end

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
