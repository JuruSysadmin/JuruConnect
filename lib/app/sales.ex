defmodule App.Sales do
  @moduledoc """
  Contexto para gerenciar vendas individuais do sistema.
  """

  @doc """
  Retorna o faturamento total por hora para um determinado dia.
  O resultado é uma lista de mapas: [%{hour: 0..23, total_sales: float}]

  Nota: Atualmente retorna uma lista vazia pois não há schema de Sale implementado.
  A funcionalidade de histórico de vendas por hora pode ser implementada futuramente.
  """
  def list_hourly_sales_history(_date \\ Date.utc_today()) do
    # TODO: Implementar schema Sale e migrations para habilitar histórico de vendas por hora
    []
  end
end
