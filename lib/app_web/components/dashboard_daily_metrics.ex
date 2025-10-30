defmodule AppWeb.DashboardDailyMetrics do
  @moduledoc """
  Componente para exibir métricas diárias do dashboard.

  Renderiza um grid de cards com informações sobre meta diária, vendas,
  devoluções, margem, notas fiscais e percentual realizado.
  """

  use Phoenix.Component
  import AppWeb.DashboardComponents

  @doc """
  Renderiza os cards de métricas diárias em um grid responsivo.
  Suporta animações para vendas, devoluções e mudanças de margem.
  """
  def daily_metrics(assigns) do
    assigns = assign_new(assigns, :animate_sale, fn -> false end)
    assigns = assign_new(assigns, :animate_devolution, fn -> false end)
    assigns = assign_new(assigns, :animate_profit, fn -> nil end)
    assigns = assign_new(assigns, :animate_diff_today, fn -> false end)
    assigns = assign_new(assigns, :diff_today_formatted, fn -> "R$ 0,00" end)
    assigns = assign_new(assigns, :diff_today_title, fn -> "Diferença para Meta" end)
    assigns = assign_new(assigns, :show_diff_today, fn -> false end)

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
      |> assign(:diff_card, render_diff_card(assigns))

    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-3 xl:grid-cols-3 gap-2 sm:gap-2.5 md:gap-3 h-full w-full min-w-0">
      <.card title="Meta Dia" value={@objetivo} subtitle=""></.card>
      <.card title="Venda Dia" value={@sale} subtitle="" animate={@animate_sale} animate_type="sale"></.card>
      <.card title="Devolução Dia" value={@devolution} subtitle="" animate={@animate_devolution} animate_type="devolution"></.card>
      {@diff_card}
      <.card title="% Realizado Dia" value={@realizado_hoje_formatted} subtitle=""></.card>
      <.card title="% Objetivo Hora Dia" value={@percentual_objetivo_hora_formatted} subtitle=""></.card>
      <.card title="Margem Dia" value={@profit} subtitle="" animate={@profit_animate} animate_type={@profit_animate_class}></.card>
      <.card title="NFs Dia " value={@nfs} subtitle=""></.card>
      <.card title="Ticket Médio Dia" value={@ticket_medio_diario} subtitle=""></.card>
    </div>
    """
  end

  defp render_diff_card(%{show_diff_today: true} = assigns) do
    ~H"""
    <.card title={assigns.diff_today_title} value={assigns.diff_today_formatted} subtitle="" animate={assigns.animate_diff_today} animate_type="diff_today"></.card>
    """
  end

  defp render_diff_card(_assigns) do
    nil
  end
end
