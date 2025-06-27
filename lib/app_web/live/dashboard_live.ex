defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view

  alias App.DashboardDataServer
  import AppWeb.DashboardComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1000, self(), :fetch_data)

    # Busca dados iniciais do GenServer
    socket = fetch_and_assign_data(socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:fetch_data, socket) do
    socket = fetch_and_assign_data(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Mantém a funcionalidade de tick para animações visuais
    socket = update(socket, :tick, &(&1 + 1))
    {:noreply, socket}
  end

  defp fetch_and_assign_data(socket) do
    state = DashboardDataServer.get_data()
    data = state.data || %{}
    api_status = state.api_status
    api_error = state.api_error
    last_update = state.last_update

    if api_status == :ok do
      assign_success_data(socket, data)
      |> assign(api_status: api_status, last_update: last_update)
    else
      assign_error_data(socket, api_error)
      |> assign(last_update: last_update)
    end
  end

  defp assign_success_data(socket, data) do
    assigns = [
      faturamento: assign_faturamento(data),
      objetivo: assign_objetivo(data),
      realizado: assign_realizado(data),
      margem: assign_margem(data),
      cupons: assign_cupons(data),
      ticket: assign_ticket(data),
      objetivo_hoje: assign_objetivo_hoje(data),
      venda_hoje: assign_venda_hoje(data),
      nfs_hoje: assign_nfs_hoje(data),
      devolucao: assign_devolucao(data),
      objetivo_hora: assign_objetivo_hora(data),
      percentual_objetivo_hora: assign_percentual_objetivo_hora(data),
      mix: assign_mix(data),
      desconto: assign_desconto(data),
      activities: generate_activities(data),
      tick: socket.assigns[:tick] || 0,
      last_update: DateTime.utc_now(),
      api_status: :ok
    ]
    assign(socket, assigns)
  end

  defp assign_faturamento(data), do: format_money(data["sale"] || 0.0)
  defp assign_objetivo(data), do: format_money(data["objetive"] || 0.0)
  defp assign_realizado(data), do: format_percent(data["percentualSale"] || 0.0)
  defp assign_margem(data), do: format_percent(calculate_margin(data))
  defp assign_cupons(data), do: data["nfs"] || 0
  defp assign_ticket(data), do: format_money(calculate_ticket(data))
  defp assign_objetivo_hoje(data), do: format_money(data["objetiveToday"] || 0.0)
  defp assign_venda_hoje(data), do: format_money(data["saleToday"] || 0.0)
  defp assign_nfs_hoje(data), do: data["nfsToday"] || 0
  defp assign_devolucao(data), do: format_money(data["devolution"] || 0.0)
  defp assign_objetivo_hora(data), do: format_money(data["objetiveHour"] || 0.0)
  defp assign_percentual_objetivo_hora(data), do: format_percent(data["percentualObjetiveHour"] || 0.0)
  defp assign_mix(data), do: data["mix"] || 0
  defp assign_desconto(data), do: format_money(data["discount"] || 0.0)

  defp extract_faturamento(data), do: data["sale"] || 0.0

  defp extract_objetivo(data), do: data["objetive"] || 0.0

  defp extract_realizado(data), do: data["percentualSale"] || 0.0

  defp extract_cupons(data), do: data["nfs"] || 0

  defp extract_objetivo_hoje(data), do: data["objetiveToday"] || 0.0

  defp extract_venda_hoje(data), do: data["saleToday"] || 0.0

  defp extract_nfs_hoje(data), do: data["nfsToday"] || 0

  defp extract_devolucao(data), do: data["devolution"] || 0.0

  defp extract_objetivo_hora(data), do: data["objetiveHour"] || 0.0

  defp extract_percentual_objetivo_hora(data), do: data["percentualObjetiveHour"] || 0.0

  defp extract_mix(data), do: data["mix"] || 0

  defp extract_desconto(data), do: data["discount"] || 0.0

  defp extract_api_data(data) do
    [
      faturamento: extract_faturamento(data),
      objetivo: extract_objetivo(data),
      realizado: extract_realizado(data),
      margem: calculate_margin(data),
      cupons: extract_cupons(data),
      ticket: calculate_ticket(data),
      objetivo_hoje: extract_objetivo_hoje(data),
      venda_hoje: extract_venda_hoje(data),
      nfs_hoje: extract_nfs_hoje(data),
      devolucao: extract_devolucao(data),
      objetivo_hora: extract_objetivo_hora(data),
      percentual_objetivo_hora: extract_percentual_objetivo_hora(data),
      mix: extract_mix(data),
      desconto: extract_desconto(data),
      activities: generate_activities(data)
    ]
  end

  defp assign_error_data(socket, reason) do
    assign(socket,
      faturamento: 0,
      objetivo: 0,
      realizado: 0,
      margem: 0,
      cupons: 0,
      ticket: 0,
      objetivo_hoje: 0,
      venda_hoje: 0,
      nfs_hoje: 0,
      devolucao: 0,
      objetivo_hora: 0,
      percentual_objetivo_hora: 0,
      mix: 0,
      desconto: 0,
      activities: [],
      api_status: :error,
      api_error: reason,
      last_update: socket.assigns[:last_update] || nil
    )
  end

  defp calculate_margin(data) do
    sale = data["sale"] || 0.0
    discount = data["discount"] || 0.0

    if sale > 0 do
      ((sale - discount) / sale) * 100
    else
      0.0
    end
  end

  defp calculate_ticket(data) do
    sale = data["sale"] || 0.0
    nfs = data["nfs"] || 1

    if nfs > 0 do
      sale / nfs
    else
      0.0
    end
  end

  defp generate_activities(data) do
    activities = []

    # Adiciona atividade de meta baseada no percentual de venda
    if data["percentualSale"] do
      activities = activities ++ [
        %{
          type: :meta,
          loja: "Loja Principal",
          percent: data["percentualSale"]
        }
      ]
    end

    # Adiciona atividade de venda do dia
    if data["saleToday"] && data["saleToday"] > 0 do
      activities = activities ++ [
        %{
          type: :venda,
          user: "Sistema",
          valor: data["saleToday"]
        }
      ]
    end

    # Adiciona atividade de mix de produtos
    if data["mix"] && data["mix"] > 0 do
      activities = activities ++ [
        %{
          type: :produto,
          marca: "Mix de #{data["mix"]} produtos"
        }
      ]
    end

    activities
  end

  defp format_money(value) when is_number(value) do
    "R$\u00A0" <>
      (value
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")
      |> add_thousands_separator())
  end
  defp format_money(_), do: "R$ 0,00"

  defp format_percent(value) when is_number(value) do
    value
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>("%")
  end
  defp format_percent(_), do: "0,00%"

  defp add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = int |> String.reverse() |> String.replace(~r/(...)(?=.)/, "\\1.") |> String.reverse()
    int <> "," <> frac
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-white">
      <!-- Sidebar -->
      <div class="fixed left-0 top-0 h-full w-64 bg-white shadow-sm border-r border-gray-200 flex flex-col z-10">
        <!-- Header -->
        <div class="p-6 border-b border-gray-100">
          <div class="flex items-center space-x-3">
            <div>
              <h2 class="text-lg font-medium text-gray-900">Jurunenese</h2>
              <p class="text-sm text-gray-500">Admin Panel</p>
            </div>
          </div>
        </div>
        <!-- Navigation -->
        <nav class="flex-1 p-4 space-y-1">
          <a href="/buscar-pedido" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
            </svg>
            Buscar Pedido
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5a2 2 0 012-2h4a2 2 0 012 2v6H8V5z"/>
            </svg>
            Dashboard
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
            </svg>
            Forms
            <span class="ml-auto bg-gray-200 text-gray-700 text-xs px-2 py-1 rounded-full">12</span>
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
            </svg>
            Submissions
            <span class="ml-auto bg-red-100 text-red-700 text-xs px-2 py-1 rounded-full">3</span>
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
            </svg>
            Analytics
          </a>
          <div class="border-t border-gray-200 my-4"></div>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"/>
            </svg>
            Team
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
            </svg>
            Settings
          </a>
          <a href="#" class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group">
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
            Help & Support
          </a>
        </nav>
        <!-- User Profile -->
        <div class="p-4 border-t border-gray-200">
          <div class="flex items-center space-x-3">
            <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-600 rounded-full flex items-center justify-center">
              <span class="text-white text-sm font-medium">JD</span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-gray-900 truncate">John Doe</p>
              <p class="text-xs text-gray-500 truncate">john@formstack.com</p>
            </div>
            <button class="p-1 text-gray-400 hover:text-gray-600">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
      <!-- Main Content Area -->
      <div class="flex-1 ml-64 flex flex-col items-center py-12 px-4 sm:px-8 bg-white">
        <div class="flex items-center justify-between w-full max-w-6xl mb-8">
          <h1 class="text-4xl font-extrabold text-gray-900 tracking-tight">Dashboard</h1>
          <div class="flex items-center space-x-4">
            <!-- Status da API -->
            <div class="flex items-center space-x-2">
              <div class={["w-3 h-3 rounded-full", if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")]}/>
              <span class="text-sm text-gray-600">
                <%= if @api_status == :ok, do: "API Online", else: "API Offline" %>
              </span>
            </div>
          </div>
        </div>

        <!-- Cards: Grid responsiva, centralizada, espaçamento amplo -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-8 w-full max-w-7xl mx-auto items-stretch mb-12">
          <.card title="Faturamento" value={@faturamento} subtitle="Líquido" icon_bg="bg-green-50">
            <:icon>
              <svg class="w-6 h-6 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 1.343-3 3s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3zm0 0V4m0 16v-4"/></svg>
            </:icon>
          </.card>
          <.card title="Realizado" value={@realizado} subtitle="Meta" icon_bg="bg-blue-50">
            <:icon>
              <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3"/></svg>
            </:icon>
          </.card>
          <.card title="Margem" value={@margem} subtitle="Líquida" icon_bg="bg-yellow-50">
            <:icon>
              <svg class="w-6 h-6 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a5 5 0 00-10 0v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2z"/></svg>
            </:icon>
          </.card>
          <.card title="NFS" value={@cupons} subtitle={"Ticket Médio " <> @ticket} icon_bg="bg-indigo-50">
            <:icon>
              <svg class="w-6 h-6 text-indigo-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h8"/></svg>
            </:icon>
          </.card>
          <.card title="Vendas Hoje" value={@venda_hoje} subtitle={"Meta: " <> @objetivo_hoje} icon_bg="bg-pink-50">
            <:icon>
              <svg class="w-6 h-6 text-pink-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/></svg>
            </:icon>
          </.card>
          <.card title="Devoluções" value={@devolucao} subtitle={"Desconto: " <> @desconto} icon_bg="bg-red-50">
            <:icon>
              <svg class="w-6 h-6 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/></svg>
            </:icon>
          </.card>
          <.card title="Mix de Produtos" value={@mix} subtitle="Produtos diferentes" icon_bg="bg-purple-50">
            <:icon>
              <svg class="w-6 h-6 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>
            </:icon>
          </.card>
        </div>

        <!-- Metas & Atividades -->
        <div class="bg-white rounded-xl shadow-lg border border-gray-100 w-full max-w-6xl">
          <div class="p-6 border-b border-gray-100">
            <h2 class="text-lg font-semibold text-gray-900">Metas & Atividades</h2>
          </div>
          <div class="p-6 space-y-4">
            <%= for activity <- @activities do %>
              <%= case activity do %>
                <% %{type: :meta, loja: loja, percent: percent} -> %>
                  <div class="flex items-center text-sm text-blue-700">
                    <span class="font-bold mr-2">Metas</span>
                    Loja <span class="font-semibold ml-1 mr-1"><%= loja %></span>:
                    <span class="ml-1"><%= percent %>% atingida</span>
                  </div>
                <% %{type: :venda, user: user, valor: valor} -> %>
                  <div class="flex items-center text-sm text-green-700">
                    <span class="font-bold mr-2">Venda</span>
                    <span><%= user %> vendeu </span>
                    <span class="font-semibold ml-1">R$ <%= :erlang.float_to_binary(:erlang.float(valor), decimals: 2) %></span>
                  </div>
                <% %{type: :produto, marca: marca} -> %>
                  <div class="flex items-center text-sm text-yellow-700">
                    <span class="font-bold mr-2">Produto em Alta</span>
                    <span>Marca <span class="font-semibold ml-1"><%= marca %></span></span>
                  </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <!-- Mensagem de erro da API -->
        <%= if @api_status == :error do %>
          <div class="mt-8 bg-red-50 border border-red-200 rounded-lg p-4 w-full max-w-6xl">
            <div class="flex items-center">
              <svg class="w-5 h-5 text-red-400 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
              <span class="text-red-800 font-medium">Erro na API:</span>
              <span class="text-red-700 ml-2"><%= @api_error %></span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
