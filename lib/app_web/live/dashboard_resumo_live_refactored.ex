defmodule AppWeb.DashboardResumoLiveRefactored do
  @moduledoc """
  LiveView refatorado usando o Context Pattern para o dashboard resumo.
  """

  use AppWeb, :live_view
  import AppWeb.DashboardComponents

  alias App.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
      Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
      Phoenix.PubSub.subscribe(App.PubSub, "sales:feed")
    end

    socket =
      socket
      |> assign_initial_state()
      |> load_dashboard_data()

    {:ok, socket}
  end



  @impl true
  def handle_info({:dashboard_updated, _data}, socket) do
    socket = load_dashboard_data(socket)
    {:noreply, push_gauge_update(socket)}
  end

  @impl true
  def handle_info({:daily_goal_achieved, goal_data}, socket) do
    celebration_id = Map.get(goal_data, :celebration_id, System.unique_integer([:positive]))

    socket =
      socket
      |> add_celebration_notification(goal_data, celebration_id)
      |> push_celebration_event(goal_data, celebration_id)


    Process.send_after(self(), {:hide_specific_notification, celebration_id}, 8000)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_sale, sale_data}, socket) do
    updated_feed =
      [format_sale_for_feed(sale_data) | socket.assigns.sales_feed]
      |> Enum.take(15)

    {:noreply, assign(socket, sales_feed: updated_feed)}
  end

  @impl true
  def handle_info({:hide_specific_notification, celebration_id}, socket) do
    updated_notifications =
      socket.assigns.notifications
      |> Enum.reject(&(&1.celebration_id == celebration_id))

    show_celebration = length(updated_notifications) > 0

    {:noreply,
     assign(socket,
       notifications: updated_notifications,
       show_celebration: show_celebration
     )}
  end

  # Event Handlers - Focados apenas na interação

  @impl true
  def handle_event("test_goal_achieved", _params, socket) do
    case Dashboard.simulate_goal_achievement() do
      {:ok, _result} ->
        socket = put_flash(socket, :info, "Teste de meta atingida executado!")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Erro no teste: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("simulate_sale", _params, socket) do
    case Dashboard.simulate_sale() do
      {:ok, _sale} ->
        socket = put_flash(socket, :info, "Venda simulada com sucesso!")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Erro na simulação: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_dashboard", %{"period" => period} = params, socket) do
    filters = %{
      period: String.to_atom(period),
      stores: Map.get(params, "stores", [])
    }

    socket = load_dashboard_data(socket, filters)
    {:noreply, socket}
  end

  @impl true
  def handle_event("export_data", %{"format" => format}, socket) do
    case Dashboard.export_data(socket.assigns.metrics, format) do
      {:ok, export_data} ->
        filename = "dashboard_#{Date.utc_today()}.#{format}"
        socket = push_event(socket, "download", %{filename: filename, data: export_data})
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Erro na exportação: #{reason}")
        {:noreply, socket}
    end
  end

  # Private Functions - Muito mais limpo e focado

  defp assign_initial_state(socket) do
    assign(socket,
      loading: true,
      notifications: [],
      show_celebration: false,
      sales_feed: [],
      alerts: [],
      metrics: %{},
      filters: %{}
    )
  end

  defp load_dashboard_data(socket, filters \\ %{}) do
    socket = assign(socket, loading: true)

    case Dashboard.get_metrics(filters) do
      {:ok, metrics} ->
        socket
        |> assign_success_state(metrics)
        |> load_additional_data()

      {:error, reason} ->
        assign_error_state(socket, reason)
    end
  end

  defp assign_success_state(socket, metrics) do
    assign(socket,
      metrics: metrics,
      # Dados formatados para compatibilidade com template existente
      sale: metrics.sales.formatted,
      cost: metrics.costs.formatted,
      # Usar função do context
      devolution: format_money(metrics.costs.devolutions),
      objetivo: metrics.goal.formatted,
      profit: metrics.profit.formatted,
      percentual: metrics.goal.formatted_percentage,
      percentual_num: metrics.goal.percentage,
      percentual_sale: metrics.percentages.yesterday_completion,
      realizado_hoje_percent: metrics.goal.percentage,
      realizado_hoje_formatted: metrics.goal.formatted_percentage,
      nfs: metrics.nfs_count,
      sale_num: metrics.sales.total,
      objetivo_num: metrics.goal.total,
      lojas_data: format_stores_for_template(metrics.stores),
      last_update: metrics.last_update,
      api_status: metrics.api_status,
      loading: false,
      api_error: nil
    )
  end

  defp assign_error_state(socket, reason) do
    assign(socket,
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "0,00%",
      percentual: "0,00%",
      percentual_num: 0,
      percentual_sale: 0,
      realizado_hoje_percent: 0,
      realizado_hoje_formatted: "0,00%",
      nfs: 0,
      lojas_data: [],
      api_status: :error,
      api_error: reason,
      loading: false,
      last_update: socket.assigns[:last_update]
    )
  end

  defp load_additional_data(socket) do
    # Carrega dados adicionais em paralelo
    tasks = [
      Task.async(fn -> Dashboard.get_alerts() end),
      Task.async(fn -> Dashboard.get_sales_feed() end)
    ]

    results = Task.await_many(tasks, 5000)

    socket
    |> assign_alerts(Enum.at(results, 0))
    |> assign_sales_feed(Enum.at(results, 1))
  end

  defp assign_alerts(socket, {:ok, alerts}) do
    assign(socket, alerts: alerts)
  end

  defp assign_alerts(socket, _), do: assign(socket, alerts: [])

  defp assign_sales_feed(socket, {:ok, sales_feed}) do
    assign(socket, sales_feed: sales_feed)
  end

  defp assign_sales_feed(socket, _), do: assign(socket, sales_feed: [])

  defp add_celebration_notification(socket, goal_data, celebration_id) do
    new_notification = %{
      id: celebration_id,
      store_name: goal_data.store_name,
      achieved: goal_data.achieved,
      target: goal_data.target,
      percentage: goal_data.percentage,
      timestamp: goal_data.timestamp,
      celebration_id: celebration_id
    }

    updated_notifications =
      [new_notification | socket.assigns.notifications]
      |> Enum.take(10)

    assign(socket,
      notifications: updated_notifications,
      show_celebration: true
    )
  end

  defp push_celebration_event(socket, goal_data, celebration_id) do
    push_event(socket, "goal-achieved-multiple", %{
      store_name: goal_data.store_name,
      achieved: format_money(goal_data.achieved),
      celebration_id: celebration_id,
      timestamp: DateTime.to_unix(goal_data.timestamp, :millisecond)
    })
  end

  defp push_gauge_update(socket) do
    push_event(socket, "update-gauge", %{
      value: socket.assigns.percentual_num
    })
  end

  defp format_sale_for_feed(sale_data) do
    %{
      id: sale_data.id,
      seller_name: sale_data.seller_name,
      seller_initials: sale_data.seller_initials,
      amount: sale_data.amount,
      product: sale_data.product,
      category: sale_data.category,
      brand: sale_data.brand,
      status: sale_data.status,
      timestamp: sale_data.timestamp,
      color: sale_data.color
    }
  end

  defp format_stores_for_template(stores) do
    # Converte formato do Context para formato esperado pelo template
    Enum.map(stores, fn store ->
      %{
        nome: store.name,
        meta_dia: store.daily_goal,
        meta_hora: store.hourly_goal,
        venda_dia: store.daily_sales,
        qtde_nfs: store.invoices_count,
        perc_hora: store.hourly_percentage,
        perc_dia: store.daily_percentage,
        status: store.status
      }
    end)
  end

  defp format_money(amount), do: Dashboard.format_money(amount)

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> Calendar.strftime(datetime, "%d/%m")
    end
  end

  @impl true
  def render(assigns) do
    # Usar o mesmo template existente
    AppWeb.DashboardResumoLive.render(assigns)
  end
end
