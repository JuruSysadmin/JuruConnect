defmodule AppWeb.DashboardComponents do
  @moduledoc """
  Componentes reutilizáveis para o dashboard de vendas.

  Inclui cards de métricas, barras de progresso e outros elementos
  visuais padronizados para manter consistência na interface.
  """

  use Phoenix.Component

  def card(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)
    assigns = assign_new(assigns, :animate, fn -> false end)
    assigns = assign_new(assigns, :animate_type, fn -> "sale" end)

    animate_class = case {assigns.animate, assigns.animate_type} do
      {true, "sale"} -> "animate-pulse-sale"
      {true, "devolution"} -> "animate-pulse-devolution"
      {true, "profit_up"} -> "animate-pulse-profit-up"
      {true, "profit_down"} -> "animate-pulse-profit-down"
      _ -> ""
    end

    assigns = assign(assigns, :animate_class, animate_class)

    ~H"""
    <div class={[
      @class,
      "bg-white rounded-xl sm:rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-3 sm:p-4 h-full transition-all duration-300 hover:shadow-xl hover:scale-105",
      @animate_class
    ]}>
      <div class="flex items-center mb-1.5 sm:mb-2">
        <span class="text-xs sm:text-sm font-medium text-gray-700 text-center leading-tight">{@title}</span>
      </div>
      <div class="text-sm sm:text-base md:text-lg lg:text-xl font-semibold text-gray-900 mb-0.5 sm:mb-1 w-full text-center">
        {@value}
      </div>
      <%= if @subtitle != "" do %>
        <div class="text-xs text-gray-500">{@subtitle}</div>
      <% end %>
    </div>
    """
  end

  def progress_bar(assigns) do
    percentual_num =
      case assigns[:percentual_num] do
        n when is_number(n) ->
          n

        s when is_binary(s) ->
          s
          |> String.replace([",", "%"], fn
            "," -> "."
            "%" -> ""
          end)
          |> String.to_float()

        _ ->
          0.0
      end

    bar_color = get_bar_color(percentual_num)

    assigns = assign(assigns, :percentual_num, percentual_num)
    assigns = assign(assigns, :bar_color, bar_color)

    ~H"""
    <div class="w-full max-w-xs mx-auto mt-6 sm:mt-8">
      <div class="flex justify-between mb-1">
        <span class="text-xs sm:text-sm font-medium text-gray-700">Meta: {@objetivo}</span>
        <span class="text-xs sm:text-sm font-medium text-gray-700">{@percentual}</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-4 sm:h-6 shadow-inner relative overflow-hidden">
        <div
          class={"h-4 sm:h-6 rounded-full bg-gradient-to-r transition-all duration-700 ease-in-out absolute left-0 top-0 flex items-center justify-end px-1 sm:px-2 text-xs font-medium text-white shadow " <> @bar_color}
          style={"width: #{min(@percentual_num, 100)}%; min-width: 2rem sm:min-width: 2.5rem;"}
        >
          <span class="drop-shadow">
            {@percentual}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp get_bar_color(percentual_num) when percentual_num < 50, do: "from-red-500 to-yellow-400"
  defp get_bar_color(percentual_num) when percentual_num < 80, do: "from-yellow-400 to-green-400"
  defp get_bar_color(_percentual_num), do: "from-green-500 to-green-400"
end
