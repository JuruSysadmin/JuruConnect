defmodule AppWeb.SupervisorModal do
  use Phoenix.Component
  import AppWeb.CoreComponents, only: [modal: 1]
  import AppWeb.DashboardUtils, only: [format_money: 1, format_percent: 1]

  @doc """
  Modal de detalhes do supervisor/vendedor, enterprise, mobile first.
  Props:
    - show: booleano para exibir/ocultar
    - supervisor_data: lista de mapas (dados do supervisor)
    - on_close: evento phx-click para fechar
    - loading: estado de carregamento (opcional)
  """
  def supervisor_modal(assigns) do
    assigns = assigns
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:supervisor_data, fn -> [] end)

    ~H"""
    <.modal id="supervisor-modal" show={@show} on_close={@on_close}>
      <div class="w-full max-w-full">
        <%= if @loading do %>
          <.loading_state />
        <% else %>
          <%= if Enum.empty?(@supervisor_data) do %>
            <.empty_state />
          <% else %>
            <.supervisor_table supervisor_data={@supervisor_data} />
          <% end %>
        <% end %>
      </div>
    </.modal>
    """
  end

  defp supervisor_table(assigns) do
    ~H"""
    <div class="overflow-x-auto -mx-2 sm:mx-0">
      <table class="w-full min-w-0 divide-y divide-gray-200 rounded-xl shadow border border-gray-100 bg-white" role="table" aria-label="Detalhes dos vendedores">
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
          <%= for {s, index} <- Enum.with_index(@supervisor_data) do %>
            <tr class="hover:bg-gray-50 transition" id={"seller-row-#{index}"}>
              <td class="px-2 py-2 border-r border-gray-100 font-medium text-gray-900 whitespace-nowrap truncate">
                <%= safe_value(s, "sellerName", "") %>
              </td>
              <td class="px-2 py-2 border-r border-gray-100 text-gray-700 whitespace-nowrap truncate">
                <%= safe_value(s, "sellerId", "") %>
              </td>
              <td class="px-2 py-2 border-r border-gray-100 text-right text-blue-700 font-mono whitespace-nowrap truncate">
                <%= format_percent(safe_value(s, "percentualObjective", 0.0)) %>
              </td>
              <td class="px-2 py-2 border-r border-gray-100 text-right text-blue-700 font-mono whitespace-nowrap truncate">
                <%= format_money(safe_value(s, "saleValue", 0.0)) %>
              </td>
              <td class="px-2 py-2 border-r border-gray-100 text-right text-gray-900 font-mono whitespace-nowrap truncate">
                <%= format_money(safe_value(s, "objetivo", 0.0)) %>
              </td>
              <td class="px-2 py-2 text-right text-gray-700 border-r border-gray-100 truncate">
                <%= safe_value(s, "qtdeInvoice", 0) %>
              </td>
              <td class="px-2 py-2 text-right text-gray-700 border-r border-gray-100 truncate">
                <%= safe_value(s, "qtdeInvoiceDay", 0) %>
              </td>
              <td class="px-4 py-2 text-right text-gray-700 border-r border-gray-100 truncate">
                <%= format_money(safe_value(s, "ticket", 0.0)) %>
              </td>
              <td class="px-4 py-2 text-right text-red-700 font-mono border-r border-gray-100 truncate">
                <%= format_money(safe_value(s, "devolution", 0.0)) %>
              </td>
              <td class="px-4 py-2 text-right text-red-700 font-mono truncate">
                <%= format_money(abs(safe_value(s, "dif", 0.0))) %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp loading_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 px-4" role="status" aria-label="Carregando dados dos vendedores">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mb-4"></div>
      <p class="text-sm text-gray-600">Carregando dados dos vendedores...</p>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 px-4 text-center">
      <svg class="w-16 h-16 text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
      </svg>
      <h3 class="text-sm font-medium text-gray-900 mb-2">Nenhum vendedor encontrado</h3>
      <p class="text-xs text-gray-500">Não há dados de vendedores disponíveis para este supervisor no momento.</p>
    </div>
    """
  end

  defp safe_value(map, key, default) when is_map(map) do
    Map.get(map, key, default)
  end
  defp safe_value(_not_map, _key, default), do: default
end
