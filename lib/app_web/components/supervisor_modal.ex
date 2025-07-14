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
      <div class="w-full max-w-full">
        <table class="w-full min-w-0 divide-y divide-gray-200 rounded-xl shadow border border-gray-100 bg-white">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-100 whitespace-nowrap truncate">VENDEDOR</th>
              <th class="px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-100 whitespace-nowrap truncate">MATRICULA</th>
              <th class="px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-100 whitespace-nowrap truncate">PROGRESSO DIÁRIO (%)</th>
              <th class="px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-100 whitespace-nowrap truncate">VENDAS MENSAIS</th>
              <th class="px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-100 whitespace-nowrap truncate">META MENSAL</th>
              <th class="px-2 py-2 text-right text-xs font-medium text-gray-500 uppercase border-r border-gray-100 truncate">Notas(mês)</th>
              <th class="px-2 py-2 text-right text-xs font-medium text-gray-500 uppercase border-r border-gray-100 truncate">Notas(dia)</th>
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase border-r border-gray-100 truncate">Ticket Médio</th>
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase border-r border-gray-100 truncate">Devoluções</th>
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase truncate">Falta para a Meta</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-100">
            <%= for s <- @supervisor_data do %>
              <tr class="hover:bg-gray-50 transition">
                <td class="px-2 py-2 border-r border-gray-100 font-medium text-gray-900 whitespace-nowrap truncate"><%= s["sellerName"] %></td>
                <td class="px-2 py-2 border-r border-gray-100 text-gray-700 whitespace-nowrap truncate"><%= s["sellerId"] %></td>
                <td class="px-2 py-2 border-r border-gray-100 text-right text-blue-700 font-mono whitespace-nowrap truncate">
                  <%= :erlang.float_to_binary((s["percentualObjective"] || 0) * 1.0, decimals: 1) %>%
                </td>
                <td class="px-2 py-2 border-r border-gray-100 text-right text-blue-700 font-mono whitespace-nowrap truncate"><%= format_money(s["saleValue"]) %></td>
                <td class="px-2 py-2 border-r border-gray-100 text-right text-gray-900 font-mono whitespace-nowrap truncate"><%= format_money(s["objetivo"]) %></td>
                <td class="px-2 py-2 text-right text-gray-700 border-r border-gray-100 truncate"><%= s["qtdeInvoice"] %></td>
                <td class="px-2 py-2 text-right text-gray-700 border-r border-gray-100 truncate"><%= s["qtdeInvoiceDay"] %></td>
                <td class="px-4 py-2 text-right text-gray-700 border-r border-gray-100 truncate"><%= format_money(s["ticket"]) %></td>
                <td class="px-4 py-2 text-right text-red-700 font-mono border-r border-gray-100 truncate"><%= format_money(s["devolution"]) %></td>
                <td class="px-4 py-2 text-right text-red-700 font-mono truncate"><%= format_money(abs(s["dif"])) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </.modal>
    """
  end
end
