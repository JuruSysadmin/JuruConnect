defmodule App.Dashboard do
  @moduledoc """
  Utilitários para formatação de valores monetários.
  """

  def format_money(value) when is_number(value) do
    # Formato brasileiro: R$ 1.234,56
    formatted =
      value
      |> Float.round(2)
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")

    "R$ #{formatted}"
  end

  def format_money(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_money(num)
      :error -> "R$ 0,00"
    end
  end

  def format_money(_), do: "R$ 0,00"
end
