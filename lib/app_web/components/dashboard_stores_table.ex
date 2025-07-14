defmodule AppWeb.DashboardStoresTable do
  use Phoenix.Component
  import AppWeb.DashboardUtils

  @doc """
  Renderiza a tabela de performance das lojas (desktop/tablet) e cards mobile.
  Props:
    - lojas_data: lista de lojas
    - loading: boolean
  """
  def stores_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full animate-fade-in-scale text-sm hidden sm:table">
        <thead class="bg-gray-100">
          <tr>
            <th class="text-left py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">Loja</th>
            <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">Meta Dia</th>
            <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">Meta Hora</th>
            <th class="text-center py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">NFs</th>
            <th class="text-right py-3 px-4 text-sm font-medium text-gray-600 border-r border-gray-300">Venda Dia</th>
            <th class="text-center py-3 px-4 text-sm font-medium text-gray-600 tablet-hide border-r border-gray-300">% Hora</th>
            <th class="text-center py-3 px-4 text-sm font-medium text-gray-600">% Dia</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200">
          <%= if @loading do %>
            <%= for _i <- 1..5 do %>
              <tr class="animate-pulse">
                <td class="py-4 px-4 border-r border-gray-200">
                  <div class="flex items-center space-x-3">
                    <div class="w-4 h-4 bg-gray-300 rounded-full shimmer-effect"></div>
                    <div class="h-4 bg-gray-300 rounded w-32 shimmer-effect"></div>
                  </div>
                </td>
                <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                  <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                </td>
                <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                  <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                </td>
                <td class="py-4 px-4 border-r border-gray-200">
                  <div class="h-4 bg-gray-300 rounded-full w-10 mx-auto shimmer-effect"></div>
                </td>
                <td class="py-4 px-4 border-r border-gray-200">
                  <div class="h-4 bg-gray-300 rounded w-20 shimmer-effect"></div>
                </td>
                <td class="py-4 px-4 tablet-hide border-r border-gray-200">
                  <div class="h-4 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
                </td>
                <td class="py-4 px-4">
                  <div class="h-4 bg-gray-300 rounded-full w-14 mx-auto shimmer-effect"></div>
                </td>
              </tr>
            <% end %>
          <% else %>
            <%= for {loja, index} <- Enum.with_index(@lojas_data) do %>
              <tr phx-click="show_supervisor_drawer" phx-value-supervisor-id={loja.supervisor_id} class={[if(rem(index, 2) == 0, do: "bg-white", else: "bg-gray-50"), "hover:bg-gray-100 transition-colors duration-200 cursor-pointer"]}>
                <td class="py-4 px-4 border-r border-gray-200">
                  <div class="flex items-center space-x-3">
                    <div class={[
                      "w-3 h-3 rounded-full",
                      case loja.status do
                        :atingida_hora -> "bg-green-500"
                        :abaixo_meta -> "bg-red-500"
                        :sem_vendas -> "bg-gray-400"
                        _ -> "bg-yellow-500"
                      end
                    ]}></div>
                    <div>
                      <div class="font-medium text-gray-900 text-sm">{loja.nome}</div>
                    </div>
                  </div>
                </td>
                <td class="text-right py-4 px-4 tablet-hide border-r border-gray-200">
                  <span class="font-mono text-gray-800 text-sm">{format_money(loja.meta_dia)}</span>
                </td>
                <td class="text-right py-4 px-4 tablet-hide border-r border-gray-200">
                  <span class="font-mono text-gray-800 text-sm">{format_money(loja.meta_hora)}</span>
                </td>
                <td class="text-center py-4 px-4 border-r border-gray-200">
                  <span class="text-sm text-gray-800 font-medium">{loja.qtde_nfs}</span>
                </td>
                <td class="text-right py-4 px-4 border-r border-gray-200">
                  <span class={[
                    "font-mono text-sm font-medium",
                    if(loja.venda_dia >= loja.meta_dia, do: "text-green-700", else: "text-gray-800")
                  ]}>{format_money(loja.venda_dia)}</span>
                </td>
                <td class="text-center py-4 px-4 tablet-hide border-r border-gray-200">
                  <span class="text-sm text-gray-800 font-medium">
                    {if is_number(loja.perc_hora),
                      do: (loja.perc_hora * 1.0) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ","),
                      else: "0,0"}%
                  </span>
                </td>
                <td class="text-center py-4 px-4">
                  <span class={[
                    "text-sm font-medium",
                    cond do
                      is_number(loja.perc_dia) and loja.perc_dia >= 100 -> "text-green-700"
                      is_number(loja.perc_dia) and loja.perc_dia >= 80 -> "text-yellow-700"
                      true -> "text-red-700"
                    end
                  ]}>
                    {if is_number(loja.perc_dia),
                      do: (loja.perc_dia * 1.0) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ","),
                      else: "0,0"}%
                  </span>
                </td>
              </tr>
            <% end %>
          <% end %>
        </tbody>
      </table>

      <!-- Versão Mobile da Tabela (Cards) -->
      <div class="block sm:hidden space-y-2">
        <%= if @loading do %>
          <%= for _i <- 1..3 do %>
            <div class="bg-gray-50 p-3 rounded-lg animate-pulse">
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-2">
                  <div class="w-3 h-3 bg-gray-300 rounded-full shimmer-effect"></div>
                  <div class="h-4 bg-gray-300 rounded w-24 shimmer-effect"></div>
                </div>
                <div class="h-4 bg-gray-300 rounded w-16 shimmer-effect"></div>
              </div>
            </div>
          <% end %>
        <% else %>
          <%= for loja <- @lojas_data do %>
            <div class="bg-gray-50 p-3 rounded-lg">
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-2">
                  <div class={[
                    "w-3 h-3 rounded-full",
                    case loja.status do
                      :atingida_hora -> "bg-green-500"
                      :abaixo_meta -> "bg-red-500"
                      :sem_vendas -> "bg-gray-400"
                      _ -> "bg-yellow-500"
                    end
                  ]}></div>
                  <div>
                    <div class="font-medium text-gray-900 text-sm">{loja.nome}</div>
                    <div class="text-xs text-gray-500">NFs: {loja.qtde_nfs}</div>
                  </div>
                </div>
                <div class="text-right">
                  <div class="font-mono text-sm text-gray-900">{format_money(loja.venda_dia)}</div>
                  <div class="text-xs text-gray-500">
                    {if is_number(loja.perc_dia),
                      do: (loja.perc_dia * 1.0) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ","),
                      else: "0,0"}%
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
