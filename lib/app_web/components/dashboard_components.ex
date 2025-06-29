defmodule AppWeb.DashboardComponents do
  @moduledoc """
  Componentes reutilizáveis para o dashboard de vendas.

  Inclui cards de métricas, barras de progresso e outros elementos
  visuais padronizados para manter consistência na interface.
  """

  use Phoenix.Component

  def card(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <div class={@class <> " bg-white rounded-xl sm:rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-3 sm:p-4 md:p-5 w-full min-w-[140px] sm:min-w-[180px] md:min-w-[200px] transition-all duration-300 hover:shadow-xl hover:scale-105"}>
      <div class="flex items-center mb-2 sm:mb-3">
        <%= if assigns[:icon] do %>
          <div class={@icon_bg <> " w-6 h-6 sm:w-8 sm:h-8 rounded-full flex items-center justify-center mr-2 sm:mr-3"}>
            {render_slot(@icon)}
          </div>
        <% end %>
        <span class="text-xs sm:text-sm md:text-base font-medium text-gray-700 text-center leading-tight">{@title}</span>
      </div>
      <div class="text-base sm:text-lg md:text-xl lg:text-2xl font-semibold text-gray-900 mb-1 sm:mb-2 w-full text-center">
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

    bar_color =
      cond do
        percentual_num < 50 -> "from-red-500 to-yellow-400"
        percentual_num < 80 -> "from-yellow-400 to-green-400"
        true -> "from-green-500 to-green-400"
      end

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
end
