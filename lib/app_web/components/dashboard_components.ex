defmodule AppWeb.DashboardComponents do
  @moduledoc """
  Componentes reutilizáveis para o dashboard de vendas.

  Inclui cards de métricas, barras de progresso e outros elementos
  visuais padronizados para manter consistência na interface.
  """

  use Phoenix.Component

  @doc """
  Renderiza um card de métrica com título, valor e subtítulo opcional.
  Suporta animações personalizadas baseadas no tipo de evento.
  """
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
    card_style = get_card_style(@title)

    ~H"""
    <div class={[
      @class,
      "rounded-lg sm:rounded-xl shadow-lg flex flex-col items-center justify-center p-2 sm:p-2.5 h-full transition-all duration-300 hover:shadow-xl hover:scale-105 min-w-0 border",
      card_style.bg,
      card_style.border,
      @animate_class
    ]}>
      <div class="flex items-center mb-1 w-full">
        <span class={["text-xs font-semibold text-center leading-tight truncate w-full", card_style.title_color]}>
          {@title}
        </span>
      </div>
      <div class={["text-xs sm:text-sm md:text-base font-bold mb-0.5 w-full text-center truncate", card_style.value_color]}>
        {@value}
      </div>
      <%= if @subtitle != "" do %>
        <div class={["text-xs truncate w-full text-center", card_style.subtitle_color]}>
          {@subtitle}
        </div>
      <% end %>
    </div>
    """
  end

  defp get_card_style(title) do
    case title do
      "Meta Dia" -> %{
        bg: "bg-primary/10",
        border: "border-primary/30",
        title_color: "text-primary",
        value_color: "text-primary font-extrabold",
        subtitle_color: "text-primary/70"
      }

      "Venda Dia" -> %{
        bg: "bg-success/10",
        border: "border-success/30",
        title_color: "text-success",
        value_color: "text-success font-extrabold",
        subtitle_color: "text-success/70"
      }

      "Devolução Dia" -> %{
        bg: "bg-error/10",
        border: "border-error/30",
        title_color: "text-error",
        value_color: "text-error font-extrabold",
        subtitle_color: "text-error/70"
      }

      "Margem Dia" -> %{
        bg: "bg-info/10",
        border: "border-info/30",
        title_color: "text-info",
        value_color: "text-info font-extrabold",
        subtitle_color: "text-info/70"
      }

      "NFs Dia" -> %{
        bg: "bg-warning/10",
        border: "border-warning/30",
        title_color: "text-warning",
        value_color: "text-warning font-extrabold",
        subtitle_color: "text-warning/70"
      }

      "Ticket Médio Dia" -> %{
        bg: "bg-secondary/10",
        border: "border-secondary/30",
        title_color: "text-secondary",
        value_color: "text-secondary font-extrabold",
        subtitle_color: "text-secondary/70"
      }

      "% Realizado Hoje" -> %{
        bg: "bg-purple-500/10",
        border: "border-purple-500/30",
        title_color: "text-purple-600",
        value_color: "text-purple-600 font-extrabold",
        subtitle_color: "text-purple-600/70"
      }

      _ -> %{
        bg: "bg-base-100",
        border: "border-base-300",
        title_color: "text-base-content",
        value_color: "text-base-content",
        subtitle_color: "text-base-content/70"
      }
    end
  end

  @doc """
  Renderiza uma barra de progresso horizontal com gradiente de cores.
  Exibe o objetivo e o percentual atual.
  """
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

  @doc """
  Renderiza um indicador de progresso radial circular.
  A cor muda automaticamente baseada no valor: vermelho (<50), amarelo (<80), verde (>=80).
  """
  def radial_progress(assigns) do
    value = min(max(assigns.value, 0), 100)
    color_class = get_radial_color(value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:color_class, color_class)

    ~H"""
    <div class="radial-progress radial-animated {@color_class} {@class}" style={"--value: #{@value}; --size: #{@size}; --thickness: #{@thickness};"} role="progressbar" aria-valuenow={@value} aria-valuemin="0" aria-valuemax="100">
      <%= if @label do %>
        <div class="flex flex-col items-center justify-center">
          <span class="text-xl sm:text-2xl font-bold">{@label}</span>
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
