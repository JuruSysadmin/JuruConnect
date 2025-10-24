defmodule AppWeb.DashboardDailyMetrics do
  use Phoenix.Component
  import AppWeb.DashboardComponents

  @doc """
  Renderiza os cards de métricas diárias.
  Props:
    - objetivo, sale, devolution, profit, nfs, realizado_hoje_formatted, animate_sale, animate_devolution, animate_profit
  """
  def daily_metrics(assigns) do
    assigns = assign_new(assigns, :animate_sale, fn -> false end)
    assigns = assign_new(assigns, :animate_devolution, fn -> false end)
    assigns = assign_new(assigns, :animate_profit, fn -> nil end)

    profit_animate_class = case assigns.animate_profit do
      :up -> "profit_up"
      :down -> "profit_down"
      _ -> nil
    end

    profit_animate = profit_animate_class != nil

    assigns =
      assigns
      |> assign(:profit_animate_class, profit_animate_class)
      |> assign(:profit_animate, profit_animate)

    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-3 xl:grid-cols-3 gap-2.5 sm:gap-3 md:gap-4 h-full w-full">
      <.card title="Meta Diária" value={@objetivo} subtitle=""></.card>
      <.card title="Vendas Diárias" value={@sale} subtitle="" animate={@animate_sale} animate_type="sale"></.card>
      <.card title="Devoluções Diárias" value={@devolution} subtitle="" animate={@animate_devolution} animate_type="devolution"></.card>
      <.card title="Margem Diária" value={@profit} subtitle="" animate={@profit_animate} animate_type={@profit_animate_class}></.card>
      <.card title="NFs Diárias" value={@nfs} subtitle=""></.card>
      <.card title="% Realizado Hoje" value={@realizado_hoje_formatted} subtitle=""></.card>
    </div>
    """
  end
end
