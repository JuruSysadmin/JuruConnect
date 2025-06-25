defmodule AppWeb.DashboardLive.Components do
  use Phoenix.Component

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :value, :string, required: true
  attr :icon_bg_color, :string, default: "bg-gray-50"
  attr :icon_text_color, :string, default: "text-gray-500"
  slot :icon_svg, required: true

  def metric_card(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-4 md:p-8 w-full min-w-[180px] max-w-xs">
      <div class="flex items-center mb-2">
        <div class={"w-10 h-10 rounded-full #{@icon_bg_color} flex items-center justify-center mr-2"}>
          <svg
            class={"w-6 h-6 #{@icon_text_color}"}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <%= render_slot(@icon_svg) %>
          </svg>
        </div>
        <span class="text-lg font-semibold text-gray-700"><%= @title %></span>
      </div>
      <div class="text-3xl font-extrabold text-gray-900 mb-1 w-full text-center">
        <%= @value %>
      </div>
      <div class="text-xs text-gray-400"><%= @subtitle %></div>
    </div>
    """
  end
end
