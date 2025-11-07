defmodule AppWeb.DashboardStoresTable do
  @moduledoc """
  Componente Phoenix para exibir tabela de performance das lojas do dashboard.

  Renderiza uma tabela responsiva com dados de performance das lojas, incluindo:
  - Versão desktop/tablet: tabela completa com todas as colunas
  - Versão mobile: cards adaptados para telas pequenas

  Fornece estados de loading, formatação de valores monetários e percentuais,
  além de indicadores visuais de status baseados no desempenho de cada loja.
  """

  use Phoenix.Component
  import AppWeb.DashboardUtils

  @doc """
  Renderiza a tabela de performance das lojas (desktop/tablet) e cards mobile.
  Props:
    - lojas_data: lista de lojas
    - loading: boolean
    - sort_by: campo atual de ordenação (atom)
    - sort_order: ordem atual (:asc ou :desc)
  """
  def stores_table(assigns) do
    assigns = assign_new(assigns, :sort_by, fn -> :perc_hora end)
    assigns = assign_new(assigns, :sort_order, fn -> :desc end)
    ~H"""
    <div class="overflow-x-auto -mx-3 sm:mx-0">
      <table class="w-full animate-fade-in-scale text-xs hidden sm:table min-w-[800px]">
        <thead class="bg-gray-100 sticky top-0 z-10">
          <tr>
            <th class="text-left py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">Loja</th>
            <th class="text-right py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 tablet-hide border-r border-gray-300 whitespace-nowrap">Meta Dia</th>
            <th class="text-right py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 tablet-hide border-r border-gray-300 whitespace-nowrap">Meta Hora</th>
            <th class="text-center py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">NFs</th>
            <th class="text-right py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">Venda Dia</th>
            <th
              phx-click="sort_table"
              phx-value-sort-by="perc_hora"
              class={[
                "text-center py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 tablet-hide border-r border-gray-300 whitespace-nowrap",
                "cursor-pointer hover:bg-gray-200 transition-colors duration-150 select-none",
                (@sort_by == :perc_hora && "bg-gray-100") || ""
              ]}
            >
              <div class="flex items-center justify-center gap-1">
                <span>% Hora</span>
                <%= render_sort_icon(@sort_by, @sort_order, assigns) %>
              </div>
            </th>
            <th class="text-center py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">% Dia</th>
            <th class="text-right py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">Ticket</th>
            <th class="text-right py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 border-r border-gray-300 whitespace-nowrap">Devolução</th>
            <th class="text-center py-2 px-2 sm:px-3 text-xs font-medium text-gray-600 whitespace-nowrap">Orç.</th>
          </tr>
        </thead>
        <tbody>
          <%= render_table_body(assigns) %>
        </tbody>
      </table>

      <!-- Versão Mobile da Tabela (Cards) -->
      <div class="block sm:hidden space-y-2">
        <%= render_mobile_cards(assigns) %>
      </div>
    </div>
    """
  end

  @doc false
  defp loading_rows(assigns) do
    ~H"""
    <%= for {_i, index} <- Enum.with_index(1..5) do %>
      <tr class={["animate-pulse", get_row_color(index)]}>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="flex items-center space-x-2">
            <div class="w-3 h-3 bg-gray-300 rounded-full shimmer-effect"></div>
            <div class="h-3 bg-gray-300 rounded w-32 shimmer-effect"></div>
          </div>
        </td>
        <td class="py-2.5 px-3 tablet-hide border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded w-20 shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 tablet-hide border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded w-20 shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded-full w-10 mx-auto shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded w-20 shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 tablet-hide border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded w-16 shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3 border-r border-gray-200">
          <div class="h-3 bg-gray-300 rounded w-16 shimmer-effect"></div>
        </td>
        <td class="py-2.5 px-3">
          <div class="h-3 bg-gray-300 rounded-full w-10 mx-auto shimmer-effect"></div>
        </td>
      </tr>
    <% end %>
    """
  end

  @doc false
  defp store_row(assigns) do
    assigns = assign(assigns, :status_color, get_status_color(assigns.loja.status))
    assigns = assign(assigns, :row_color, get_row_color(assigns.index))
    assigns = assign(assigns, :sale_color, get_sale_color(assigns.loja.venda_dia, assigns.loja.meta_dia))
    assigns = assign(assigns, :perc_dia_formatted, format_percent_value(assigns.loja.perc_dia))
    assigns = assign(assigns, :perc_dia_color, get_percent_color(assigns.loja.perc_dia))
    assigns = assign(assigns, :perc_hora_formatted, format_percent_value(assigns.loja.perc_hora))
    assigns = assign(assigns, :animate_venda_dia, Map.get(assigns.loja, :animate_venda_dia, false))
    assigns = assign(assigns, :increment_value, Map.get(assigns.loja, :increment_value, 0.0))

    ~H"""
    <tr phx-click="show_supervisor_drawer" phx-value-supervisor-id={@loja.supervisor_id} class={[@row_color, "hover:bg-gray-100 transition-colors duration-200 cursor-pointer"]}>
      <td class="py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap max-w-[200px] overflow-hidden text-ellipsis">
        <div class="flex items-center space-x-2">
          <div class={["w-3 h-3 rounded-full flex-shrink-0", @status_color]}></div>
          <div class="font-medium text-gray-900 text-xs truncate">{@loja.nome}</div>
        </div>
      </td>
      <td class="text-right py-2.5 px-2 sm:px-3 tablet-hide border-r border-gray-200 whitespace-nowrap">
        <span class="font-mono text-gray-800 text-xs">{format_money(@loja.meta_dia)}</span>
      </td>
      <td class="text-right py-2.5 px-2 sm:px-3 tablet-hide border-r border-gray-200 whitespace-nowrap">
        <span class="font-mono text-gray-800 text-xs">{format_money(@loja.meta_hora)}</span>
      </td>
      <td class="text-center py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap">
        <span class="text-xs text-gray-800 font-medium">{@loja.qtde_nfs}</span>
      </td>
      <td class="text-right py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap">
        <%= render_venda_dia(assigns) %>
      </td>
      <td class="text-center py-2.5 px-2 sm:px-3 tablet-hide border-r border-gray-200 whitespace-nowrap">
        <span class="text-xs text-gray-800 font-medium">{@perc_hora_formatted}%</span>
      </td>
      <td class="text-center py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap">
        <span class={["text-xs font-medium", @perc_dia_color]}>{@perc_dia_formatted}%</span>
      </td>
      <td class="text-right py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap">
        <span class="font-mono text-gray-800 text-xs">{format_money(@loja.ticket)}</span>
      </td>
      <td class="text-right py-2.5 px-2 sm:px-3 border-r border-gray-200 whitespace-nowrap">
        <span class="font-mono text-red-600 text-xs">{format_money(@loja.devolution)}</span>
      </td>
      <td class="text-center py-2.5 px-2 sm:px-3 whitespace-nowrap">
        <span class="text-xs text-gray-800 font-medium">{@loja.pre_sale_qtde}</span>
      </td>
    </tr>
    """
  end

  @doc false
  defp loading_cards(assigns) do
    ~H"""
    <%= for _i <- 1..3 do %>
      <div class="bg-gray-50 p-3 rounded-lg animate-pulse">
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center space-x-2">
            <div class="w-3 h-3 bg-gray-300 rounded-full shimmer-effect"></div>
            <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
          </div>
          <div class="h-4 bg-gray-300 rounded w-16 shimmer-effect"></div>
        </div>
        <div class="grid grid-cols-3 gap-2 pt-2 border-t border-gray-200">
          <div class="h-8 bg-gray-300 rounded shimmer-effect"></div>
          <div class="h-8 bg-gray-300 rounded shimmer-effect"></div>
          <div class="h-8 bg-gray-300 rounded shimmer-effect"></div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc false
  defp store_card(assigns) do
    assigns = assign(assigns, :status_color, get_status_color(assigns.loja.status))
    assigns = assign(assigns, :perc_dia_formatted, format_percent_value(assigns.loja.perc_dia))

    ~H"""
    <div class="bg-gray-50 p-3 rounded-lg">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center space-x-2">
          <div class={["w-3 h-3 rounded-full", @status_color]}></div>
          <div>
            <div class="font-medium text-gray-900 text-sm">{@loja.nome}</div>
            <div class="text-xs text-gray-500">NFs: {@loja.qtde_nfs}</div>
          </div>
        </div>
        <div class="text-right">
          <div class="font-mono text-sm text-gray-900">{format_money(@loja.venda_dia)}</div>
          <div class="text-xs text-gray-500">{@perc_dia_formatted}%</div>
        </div>
      </div>
      <div class="grid grid-cols-3 gap-2 pt-2 border-t border-gray-200">
        <div class="text-center">
          <div class="text-xs text-gray-500 mb-0.5">Ticket</div>
          <div class="font-mono text-xs text-gray-900">{format_money(@loja.ticket)}</div>
        </div>
        <div class="text-center">
          <div class="text-xs text-gray-500 mb-0.5">Devolução</div>
          <div class="font-mono text-xs text-red-600">{format_money(@loja.devolution)}</div>
        </div>
        <div class="text-center">
          <div class="text-xs text-gray-500 mb-0.5">Orçamentos</div>
          <div class="text-xs text-gray-900 font-medium">{@loja.pre_sale_qtde}</div>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  defp get_status_color(:atingida_hora), do: "bg-green-500"
  defp get_status_color(:abaixo_meta), do: "bg-red-500"
  defp get_status_color(:sem_vendas), do: "bg-gray-400"
  defp get_status_color(_), do: "bg-yellow-500"

  @doc false
  defp get_row_color(index) when rem(index, 2) == 0, do: "bg-white"
  defp get_row_color(_), do: "bg-gray-50"

  @doc false
  defp get_sale_color(venda, meta) when venda >= meta, do: "text-green-700"
  defp get_sale_color(_, _), do: "text-gray-800"

  @doc false
  defp get_percent_color(perc) when is_number(perc) and perc >= 100, do: "text-green-700"
  defp get_percent_color(perc) when is_number(perc) and perc >= 80, do: "text-yellow-700"
  defp get_percent_color(_), do: "text-red-700"

  @doc false
  defp format_percent_value(n) when is_number(n) do
    n
    |> convert_to_float()
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace(".", ",")
  end

  defp format_percent_value(_), do: "0,0"

  @doc false
  defp convert_to_float(n) when is_float(n), do: n
  defp convert_to_float(n) when is_integer(n), do: n * 1.0
  defp convert_to_float(n) when is_binary(n) do
    case Float.parse(n) do
      {num, _} -> num
      :error -> 0.0
    end
  end
  defp convert_to_float(_n), do: 0.0


  defp render_sort_icon(:perc_hora, :desc, assigns) do
    ~H"""
    <svg class="w-3 h-3 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
    </svg>
    """
  end

  defp render_sort_icon(:perc_hora, :asc, assigns) do
    ~H"""
    <svg class="w-3 h-3 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
    </svg>
    """
  end

  defp render_sort_icon(_sort_by, _sort_order, assigns) do
    ~H"""
    <svg class="w-3 h-3 text-gray-400 opacity-0 hover:opacity-100" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
    </svg>
    """
  end

  defp render_table_body(%{loading: true} = assigns) do
    ~H"""
    <.loading_rows />
    """
  end

  defp render_table_body(%{loading: false} = assigns) do
    ~H"""
    <%= for {loja, index} <- Enum.with_index(@lojas_data) do %>
      <.store_row loja={loja} index={index} />
    <% end %>
    """
  end

  defp render_mobile_cards(%{loading: true} = assigns) do
    ~H"""
    <.loading_cards />
    """
  end

  defp render_mobile_cards(%{loading: false} = assigns) do
    ~H"""
    <%= for loja <- @lojas_data do %>
      <.store_card loja={loja} />
    <% end %>
    """
  end

  defp render_venda_dia(%{animate_venda_dia: true} = assigns) do
    ~H"""
    <div class="flex flex-col items-end gap-0.5">
      <span class={["font-mono text-xs font-medium", assigns.sale_color]}>{format_money(assigns.loja.venda_dia - assigns.increment_value)}</span>
      <span class="font-mono text-xs font-bold text-green-600 animate-pulse bg-green-100 px-2 py-0.5 rounded-full">+{format_money(assigns.increment_value)}</span>
    </div>
    """
  end

  defp render_venda_dia(assigns) do
    ~H"""
    <span class={["font-mono text-xs font-medium", assigns.sale_color]}>{format_money(assigns.loja.venda_dia)}</span>
    """
  end
end
