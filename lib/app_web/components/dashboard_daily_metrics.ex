defmodule AppWeb.DashboardDailyMetrics do
  use Phoenix.Component
  import AppWeb.DashboardComponents

  @doc """
  Renderiza os cards de métricas diárias.
  Props:
    - objetivo, sale, devolution, profit, nfs, realizado_hoje_formatted
  """
  def daily_metrics(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-3 xl:grid-cols-3 gap-3 sm:gap-4 md:gap-5">
      <.card title="Meta Diária" value={@objetivo} subtitle=""></.card>
      <.card title="Vendas Diárias" value={@sale} subtitle=""></.card>
      <.card title="Devoluções Diárias" value={@devolution} subtitle=""></.card>
      <.card title="Margem Diária" value={@profit} subtitle=""></.card>
      <.card title="NFs Diárias" value={@nfs} subtitle=""></.card>
      <.card title="% Realizado Hoje" value={@realizado_hoje_formatted} subtitle=""></.card>
    </div>
    """
  end
end
