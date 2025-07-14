defmodule AppWeb.SupervisorModal do
  use Phoenix.Component
  import AppWeb.CoreComponents, only: [modal: 1]
  import AppWeb.DashboardUtils, only: [format_money: 1]

  @doc """
  Modal de detalhes do supervisor/vendedor, enterprise, mobile first.
  Props:
    - show: booleano para exibir/ocultar
    - supervisor_data: lista de mapas (dados do supervisor)
    - on_close: evento phx-click para fechar
  """
  def supervisor_modal(assigns) do
    ~H"""
    <.modal id="supervisor-modal" show={@show} on_close={@on_close}>
      <%= for s <- @supervisor_data do %>
        <div class="rounded-xl border border-gray-200 p-6 mb-4 bg-white">
          <div class="flex items-center justify-between mb-1">
            <div class="text-xl font-bold text-gray-900"><%= s["sellerName"] %></div>
          </div>
          <div class="text-gray-400 text-sm mb-4">ID: <%= s["sellerId"] %></div>
          <div class="mb-4">
            <div class="flex items-center justify-between mb-1">
              <span class="text-sm text-gray-700">Progresso Diário</span>
              <span class="text-sm text-gray-700 font-semibold">
                <%= :erlang.float_to_binary((s["percentualObjective"] || 0) * 1.0, decimals: 1) %>%
              </span>
            </div>
            <div class="w-full h-2 bg-gray-200 rounded-full">
              <div class="h-2 bg-gray-900 rounded-full" style={"width: #{min(Float.round((s["percentualObjective"] || 0) * 1.0, 1), 100)}%"}></div>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4 mb-4">
            <div>
              <div class="text-xs text-gray-500">Vendas mensais</div>
              <div class="text-lg font-bold text-gray-900">R$ <%= format_money(s["saleValue"]) %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Objetivo mensal</div>
              <div class="text-lg font-bold text-gray-900">R$ <%= format_money(s["objetivo"]) %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Notas(mês)</div>
              <div class="text-lg font-bold text-gray-900"><%= s["qtdeInvoice"] %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Notas(dia)</div>
              <div class="text-lg font-bold text-gray-900"><%= s["qtdeInvoiceDay"] %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Ticket Médio</div>
              <div class="text-lg font-bold text-gray-900">R$ <%= format_money(s["ticket"]) %></div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Devoluções</div>
              <div class="text-lg font-bold text-gray-900">R$ <%= format_money(s["devolution"]) %></div>
            </div>
          </div>
          <hr class="my-2" />
          <div class="flex items-center justify-between mt-2">
            <span class="text-sm text-gray-600">Falta para a meta</span>
            <span class="text-base font-bold text-red-600 flex items-center">
              <svg class="w-4 h-4 mr-1 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l-4 4m0 0l-4-4m4 4V4" /></svg>
              R$ <%= format_money(abs(s["dif"])) %>
            </span>
          </div>
        </div>
      <% end %>
    </.modal>
    """
  end
end
