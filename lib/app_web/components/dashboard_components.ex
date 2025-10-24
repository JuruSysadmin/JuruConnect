defmodule AppWeb.DashboardComponents do
  @moduledoc """
  Componentes reutilizáveis para o dashboard de vendas.

  Inclui cards de métricas, barras de progresso e outros elementos
  visuais padronizados para manter consistência na interface.
  """

  use Phoenix.Component

  def card(assigns) do
    assigns
    |> assign_new(:class, fn -> "" end)
    |> assign_new(:animate, fn -> false end)
    |> assign_new(:animate_type, fn -> "sale" end)
    |> assign_animate_class()
    |> render_card()
  end

  defp assign_animate_class(assigns) do
    animate_class = get_animate_class(assigns.animate, assigns.animate_type)
    assign(assigns, :animate_class, animate_class)
  end

  defp get_animate_class(true, "sale"), do: "animate-pulse-sale"
  defp get_animate_class(true, "devolution"), do: "animate-pulse-devolution"
  defp get_animate_class(true, "profit_up"), do: "animate-pulse-profit-up"
  defp get_animate_class(true, "profit_down"), do: "animate-pulse-profit-down"
  defp get_animate_class(_animate, _type), do: ""

  defp render_card(assigns) do
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
    percentual_num = parse_percentual(assigns[:percentual_num])
    bar_color = get_bar_color(percentual_num)

    assigns
    |> assign(:percentual_num, percentual_num)
    |> assign(:bar_color, bar_color)
    |> then(&render_progress_bar/1)
  end

  defp parse_percentual(n) when is_number(n), do: n
  defp parse_percentual(s) when is_binary(s) do
    s
    |> String.replace([",", "%"], fn
      "," -> "."
      "%" -> ""
    end)
    |> String.to_float()
  end
  defp parse_percentual(_), do: 0.0

  defp render_progress_bar(assigns) do
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

  attr :value, :float, default: 0.0, doc: "Percentual de 0 a 100"
  attr :size, :string, default: "6rem", doc: "Tamanho do radial progress"
  attr :thickness, :string, default: "0.5rem", doc: "Espessura da linha do radial progress"
  attr :label, :string, default: nil, doc: "Label principal no centro"
  attr :label_bottom, :string, default: nil, doc: "Label secundário abaixo"
  attr :class, :string, default: "", doc: "Classes CSS adicionais"

  def radial_progress(assigns) do
    # Garante que o valor está entre 0 e 100
    value = min(max(assigns.value, 0), 100)

    # Determina a cor baseada no valor
    color_class = get_radial_color(value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:color_class, color_class)

    ~H"""
    <div class="radial-progress radial-animated {@color_class} {@class}" style={"--value: #{@value}; --size: #{@size}; --thickness: #{@thickness};"} role="progressbar" aria-valuenow={@value} aria-valuemin="0" aria-valuemax="100">
      <%= if @label do %>
        <div class="flex flex-col items-center justify-center">
          <span class="text-lg sm:text-xl font-bold">{@label}</span>
          <%= if @label_bottom do %>
            <span class="text-[10px] text-gray-500">{@label_bottom}</span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp get_radial_color(value) when value < 50, do: "text-error"
  defp get_radial_color(value) when value < 80, do: "text-warning"
  defp get_radial_color(_value), do: "text-success"

  defp get_bar_color(percentual_num) when percentual_num < 50, do: "from-red-500 to-yellow-400"
  defp get_bar_color(percentual_num) when percentual_num < 80, do: "from-yellow-400 to-green-400"
  defp get_bar_color(_percentual_num), do: "from-green-500 to-green-400"
end
