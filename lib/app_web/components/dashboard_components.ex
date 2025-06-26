defmodule AppWeb.DashboardComponents do
  use Phoenix.Component

  def card(assigns) do
    ~H"""
    <div class={@class <> " bg-white rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-8 w-full min-w-[200px]"}>
      <div class="flex items-center mb-2">
        <div class={@icon_bg <> " w-10 h-10 rounded-full flex items-center justify-center mr-2"}>
          <%= render_slot(@icon) %>
        </div>
        <span class="text-lg font-semibold text-gray-700"><%= @title %></span>
      </div>
      <div class="text-xl md:text-2xl font-extrabold text-gray-900 mb-1 w-full text-center">
        <%= @value %>
      </div>
      <div class="text-xs text-gray-400"><%= @subtitle %></div>
    </div>
    """
  end

  def progress_bar(assigns) do
    percentual_num =
      case assigns[:percentual_num] do
        n when is_number(n) -> n
        s when is_binary(s) ->
          s
          |> String.replace([",", "%"], fn
            "," -> "."
            "%" -> ""
          end)
          |> String.to_float()
        _ -> 0.0
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
    <div class="w-full max-w-xs mx-auto mt-8">
      <div class="flex justify-between mb-1">
        <span class="text-sm font-medium text-gray-700">Meta: <%= @objetivo %></span>
        <span class="text-sm font-medium text-gray-700"><%= @percentual %></span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-6 shadow-inner relative overflow-hidden">
        <div
          class={"h-6 rounded-full bg-gradient-to-r transition-all duration-700 ease-in-out absolute left-0 top-0 flex items-center justify-end px-2 text-xs font-bold text-white shadow " <> @bar_color}
          style={"width: #{min(@percentual_num, 100)}%; min-width: 2.5rem;"}
        >
          <span class="drop-shadow">
            <%= @percentual %>
          </span>
        </div>
      </div>
    </div>
    """
  end
end
