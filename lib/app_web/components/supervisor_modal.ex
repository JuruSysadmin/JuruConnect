defmodule AppWeb.SupervisorModal do
  @moduledoc """
  Componente Phoenix para exibir modal com detalhes dos vendedores de um supervisor.

  Fornece uma interface responsiva (mobile-first) para exibir informações detalhadas
  sobre os vendedores de um supervisor específico, incluindo:
  - Dados do vendedor (nome, matrícula)
  - Métricas de performance (progresso, vendas, metas)
  - Estatísticas (notas fiscais, ticket médio, devoluções)

  O componente gerencia estados de loading e empty state automaticamente.
  """

  use Phoenix.Component
  import AppWeb.CoreComponents, only: [modal: 1]
  import AppWeb.DashboardUtils, only: [format_money: 1, format_percent: 1]

  @doc """
  Renderiza modal com detalhes dos vendedores de um supervisor.

  ## Props

    * `show` - Booleano para exibir/ocultar o modal
    * `on_close` - Evento JS para fechar o modal
    * `loading` - Estado de carregamento (opcional, padrão: false)
    * `supervisor_data` - Lista de mapas com dados dos vendedores (opcional, padrão: [])

  ## Exemplo

      <.supervisor_modal
        show={@show_modal}
        on_close={JS.push("close_modal")}
        loading={@loading}
        supervisor_data={@sellers_data}
      />
  """
  def supervisor_modal(assigns) do
    assigns =
      assigns
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
      <table class="table table-xs sm:table-sm table-zebra w-full min-w-[800px]" aria-label="Detalhes dos vendedores">
        <thead>
          <tr>
            <th class="text-left whitespace-nowrap">VENDEDOR</th>
            <th class="text-left whitespace-nowrap">MATRICULA</th>
            <th class="text-left whitespace-nowrap">PROGRESSO DIÁRIO (%)</th>
            <th class="text-left whitespace-nowrap">VENDAS MENSAIS</th>
            <th class="text-left whitespace-nowrap">META MENSAL</th>
            <th class="text-right whitespace-nowrap">Notas(mês)</th>
            <th class="text-right whitespace-nowrap">Notas(dia)</th>
            <th class="text-right whitespace-nowrap">Ticket Médio</th>
            <th class="text-right whitespace-nowrap">Devoluções(mês)</th>
            <th class="text-right whitespace-nowrap">Falta para a Meta</th>
          </tr>
        </thead>
        <tbody>
          <%= for {s, index} <- Enum.with_index(@supervisor_data) do %>
            <tr id={"seller-row-#{index}"}>
              <td class="font-medium max-w-[150px] overflow-hidden text-ellipsis">
                <%= safe_value(s, "sellerName", "") %>
              </td>
              <td class="max-w-[100px] overflow-hidden text-ellipsis">
                <%= safe_value(s, "sellerId", "") %>
              </td>
              <td class="text-right text-primary font-mono">
                <%= format_percent(safe_value(s, "percentualObjective", 0.0)) %>
              </td>
              <td class="text-right text-primary font-mono">
                <%= format_money(safe_value(s, "saleValue", 0.0)) %>
              </td>
              <td class="text-right font-mono">
                <%= format_money(safe_value(s, "objetivo", 0.0)) %>
              </td>
              <td class="text-right">
                <%= safe_value(s, "qtdeInvoice", 0) %>
              </td>
              <td class="text-right">
                <%= safe_value(s, "qtdeInvoiceDay", 0) %>
              </td>
              <td class="text-right">
                <%= format_money(safe_value(s, "ticket", 0.0)) %>
              </td>
              <td class="text-right text-error font-mono">
                <%= format_money(safe_value(s, "devolution", 0.0)) %>
              </td>
              <td class="text-right text-error font-mono">
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
      <span class="loading loading-spinner loading-lg text-primary mb-4"></span>
      <p class="text-sm text-base-content">Carregando dados dos vendedores...</p>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 px-4 text-center">
      <svg class="w-16 h-16 text-base-content opacity-40 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
      </svg>
      <h3 class="text-sm font-medium text-base-content mb-2">Nenhum vendedor encontrado</h3>
      <p class="text-xs text-base-content opacity-60">Não há dados de vendedores disponíveis para este supervisor no momento.</p>
    </div>
    """
  end

  defp safe_value(map, key, default) when is_map(map) do
    Map.get(map, key, default)
  end
  defp safe_value(_not_map, _key, default), do: default
end
