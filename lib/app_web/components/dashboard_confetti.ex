defmodule AppWeb.DashboardConfetti do
  use Phoenix.Component

  @doc """
  Renderiza o efeito visual de confetti/celebração.
  Props:
    - notifications: lista de notificações
    - show_celebration: boolean
  """
  def confetti(assigns) do
    ~H"""
    <%= if @show_celebration do %>
      <div class="fixed inset-0 z-50 pointer-events-none">
        <%= for {_notification, index} <- Enum.with_index(@notifications) do %>
          <!-- Layer 1 - Confetti principal -->
          <div class="absolute top-0 left-[10%] w-3 h-3 bg-yellow-400 confetti" style={"animation-delay: #{index * 0.1}s;"}></div>
          <div class="absolute top-0 left-[20%] w-2 h-2 bg-green-400 confetti" style={"animation-delay: #{index * 0.1 + 0.2}s;"}></div>
          <div class="absolute top-0 left-[30%] w-3 h-3 bg-blue-400 confetti" style={"animation-delay: #{index * 0.1 + 0.4}s;"}></div>
          <div class="absolute top-0 left-[40%] w-2 h-2 bg-red-400 confetti" style={"animation-delay: #{index * 0.1 + 0.6}s;"}></div>
          <div class="absolute top-0 left-[50%] w-3 h-3 bg-purple-400 confetti" style={"animation-delay: #{index * 0.1 + 0.8}s;"}></div>
          <div class="absolute top-0 left-[60%] w-2 h-2 bg-pink-400 confetti" style={"animation-delay: #{index * 0.1 + 1.0}s;"}></div>
          <div class="absolute top-0 left-[70%] w-3 h-3 bg-indigo-400 confetti" style={"animation-delay: #{index * 0.1 + 1.2}s;"}></div>
          <div class="absolute top-0 left-[80%] w-2 h-2 bg-orange-400 confetti" style={"animation-delay: #{index * 0.1 + 1.4}s;"}></div>
          <div class="absolute top-0 left-[90%] w-3 h-3 bg-emerald-400 confetti" style={"animation-delay: #{index * 0.1 + 1.6}s;"}></div>

          <!-- Layer 2 - Confetti secundário -->
          <div class="absolute top-0 left-[15%] w-1 h-1 bg-yellow-300 confetti" style={"animation-delay: #{index * 0.1 + 0.3}s; animation-duration: 3.5s;"}></div>
          <div class="absolute top-0 left-[25%] w-1 h-1 bg-green-300 confetti" style={"animation-delay: #{index * 0.1 + 0.5}s; animation-duration: 4s;"}></div>
          <div class="absolute top-0 left-[35%] w-1 h-1 bg-blue-300 confetti" style={"animation-delay: #{index * 0.1 + 0.7}s; animation-duration: 3s;"}></div>
          <div class="absolute top-0 left-[45%] w-1 h-1 bg-red-300 confetti" style={"animation-delay: #{index * 0.1 + 0.9}s; animation-duration: 3.5s;"}></div>
          <div class="absolute top-0 left-[55%] w-1 h-1 bg-purple-300 confetti" style={"animation-delay: #{index * 0.1 + 1.1}s; animation-duration: 4s;"}></div>
          <div class="absolute top-0 left-[65%] w-1 h-1 bg-pink-300 confetti" style={"animation-delay: #{index * 0.1 + 1.3}s; animation-duration: 3s;"}></div>
          <div class="absolute top-0 left-[75%] w-1 h-1 bg-indigo-300 confetti" style={"animation-delay: #{index * 0.1 + 1.5}s; animation-duration: 3.5s;"}></div>
          <div class="absolute top-0 left-[85%] w-1 h-1 bg-orange-300 confetti" style={"animation-delay: #{index * 0.1 + 1.7}s; animation-duration: 4s;"}></div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
