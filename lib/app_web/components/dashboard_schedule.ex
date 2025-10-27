defmodule AppWeb.DashboardSchedule do
  @moduledoc """
  Componente para exibir agendamentos de entregas no dashboard.

  Renderiza cards com informações de data de entrega, peso vendido
  e peso disponível para cada agendamento.
  """

  use Phoenix.Component

  import AppWeb.DashboardUtils, only: [format_date: 1, format_weight: 1]

  @doc """
  Renderiza cards de agendamento de entregas.
  Recebe uma lista de dados de agendamento e renderiza cada item.
  """
  def schedule_card(assigns) do
    assigns = assign_new(assigns, :schedule_data, fn -> [] end)

    ~H"""
    <div class="space-y-3">
      <%= for schedule <- @schedule_data do %>
        <.schedule_item schedule={schedule} />
      <% end %>
    </div>
    """
  end

  defp schedule_item(assigns) do
    delivery_data = find_delivery_by_date(assigns.schedule)
    date = Map.get(assigns.schedule, "dateDelivery")
    assigns = assign(assigns, :delivery_data, delivery_data)
    assigns = assign(assigns, :date, date)

    ~H"""
    <div class="bg-white border border-gray-200 rounded-lg shadow-md p-4 min-w-0">
      <div class="flex items-center gap-4 flex-wrap sm:flex-nowrap">
        <.calendar_icon />
        <div class="flex-1 min-w-0">
          <%= if @date do %>
            <h3 class="font-semibold text-gray-900 text-sm truncate">Data para entrega: {format_date(@date)}</h3>
          <% else %>
            <h3 class="font-semibold text-gray-900 text-sm">Agendamento de Entrega</h3>
          <% end %>
        </div>
        <.delivery_info delivery_data={@delivery_data} />
      </div>
    </div>
    """
  end

  defp delivery_info(assigns) do
    case assigns.delivery_data do
      nil -> ~H"""
      <div class="flex items-center gap-4">
        <div class="text-xs text-gray-500 italic">Sem dados de entrega</div>
      </div>
      """
      _ ->
        assigns
        |> assign_prepare_delivery_data()
        |> assign_format_weights()
        |> render_delivery_info()
    end
  end

  defp assign_prepare_delivery_data(assigns) do
    assigns
    |> assign(:sale_weight, Map.get(assigns.delivery_data, :saleWeigth, 0) || Map.get(assigns.delivery_data, "saleWeigth", 0))
    |> assign(:available, Map.get(assigns.delivery_data, :avaliableDelivery, 0) || Map.get(assigns.delivery_data, "avaliableDelivery", 0))
  end

  defp assign_format_weights(assigns) do
    assigns
    |> assign(:formatted_sale_weight, format_weight(assigns.sale_weight))
    |> assign(:formatted_available, format_weight(assigns.available))
  end

  defp render_delivery_info(assigns) do
    ~H"""
    <div class="flex items-center gap-4 flex-wrap sm:flex-nowrap">
      <div class="bg-gray-50 rounded-lg shadow-sm px-3 py-2 flex items-center gap-2 min-w-0">
        <div class="text-xs font-medium text-green-700 whitespace-nowrap">Peso Vendido:</div>
        <div class="text-sm font-semibold text-green-900 whitespace-nowrap">{@formatted_sale_weight} kg</div>
      </div>
      <div class="bg-gray-50 rounded-lg shadow-sm px-3 py-2 flex items-center gap-2 min-w-0">
        <div class="text-xs font-medium text-blue-700 whitespace-nowrap">Disponível:</div>
        <div class="text-sm font-semibold text-blue-900 whitespace-nowrap">{@formatted_available} kg</div>
      </div>
    </div>
    """
  end

  defp find_delivery_by_date(schedule) do
    main_date = Map.get(schedule, "dateDelivery")
    deliveries = Map.get(schedule, "deliveries", [])

    deliveries
    |> Enum.find(fn delivery ->
      Map.get(delivery, "dateDelivery") == main_date
    end)
    |> map_delivery_data()
  end

  defp map_delivery_data(nil), do: nil

  defp map_delivery_data(delivery) do
    %{
      saleWeigth: Map.get(delivery, "saleWeigth", 0),
      avaliableDelivery: Map.get(delivery, "avaliableDelivery", 0)
    }
  end

  defp calendar_icon(assigns) do
    ~H"""
    <div class="flex-shrink-0 w-10 h-10 bg-blue-50 rounded-lg flex items-center justify-center">
      <svg xmlns="http://www.w3.org/2000/svg" class="stroke-blue-600 h-5 w-5" fill="none" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
      </svg>
    </div>
    """
  end
end
