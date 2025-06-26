defmodule AppWeb.DashboardResumoLive do
  use AppWeb, :live_view
  import AppWeb.DashboardComponents
  alias App.DashboardDataServer

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    socket = fetch_and_assign_data(socket)
    {:ok, socket}
  end

  @impl true
  def handle_info({:dashboard_updated, data}, socket) do
    data_with_atom_keys = for {k, v} <- data, into: %{}, do: {String.to_atom(k), v}
    socket = assign_success_data(socket, data_with_atom_keys)

    socket =
      push_event(socket, "update-gauge", %{
        value: socket.assigns.percentual_num
      })

    {:noreply, socket}
  end

  defp fetch_and_assign_data(socket) do
    state = DashboardDataServer.get_data()
    data = state.data || %{}
    data = for {k, v} <- data, into: %{}, do: {String.to_atom(k), v}
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
    percentual_num =
      (data[:percentual] || 0.0)
      |> to_string()
      |> String.replace(",", ".")
      |> String.replace("%", "")
      |> Float.parse()
      |> elem(0)

    assigns = [
      sale: format_money(data[:sale] || 0.0),
      cost: format_money(data[:cost] || 0.0),
      devolution: format_money(data[:devolution] || 0.0),
      objetivo: format_money(data[:objetivo] || 0.0),
      profit: format_percent(data[:profit] || 0.0),
      percentual: format_percent(data[:percentual] || 0.0),
      percentual_num: percentual_num,
      nfs: data[:nfs] || 0,
      last_update: DateTime.utc_now(),
      api_status: :ok
    ]
    assign(socket, assigns)
  end

  defp assign_error_data(socket, reason) do
    assign(socket,
      sale: "R$ 0,00",
      cost: "R$ 0,00",
      devolution: "R$ 0,00",
      objetivo: "R$ 0,00",
      profit: "R$ 0,00",
      percentual: "0,00%",
      percentual_num: 0,
      nfs: 0,
      api_status: :error,
      api_error: reason,
      last_update: socket.assigns[:last_update] || nil
    )
  end

  defp format_money(value) when is_number(value) do
    value = value * 1.0
    "R$\u00A0" <>
      (value
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")
      |> add_thousands_separator())
  end
  defp format_money(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_money(num)
      :error -> "R$ 0,00"
    end
  end
  defp format_money(_), do: "R$ 0,00"

  defp format_percent(value) when is_number(value) do
    value = value * 1.0
    value
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(".", ",")
    |> Kernel.<>("%")
  end
  defp format_percent(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_percent(num)
      :error -> "0,00%"
    end
  end
  defp format_percent(_), do: "0,00%"

  defp add_thousands_separator(str) do
    [int, frac] = String.split(str, ",")
    int = int |> String.reverse() |> String.replace(~r/(...)(?=.)/, "\\1.") |> String.reverse()
    int <> "," <> frac
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-white flex-col items-center py-12 px-4 sm:px-8">
      <div class="flex items-center justify-between w-full max-w-4xl mb-12">
        <h1 class="text-4xl font-extrabold text-gray-900 tracking-tight">Dashboard</h1>
        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2">
            <div class={["w-3 h-3 rounded-full", if(@api_status == :ok, do: "bg-green-500", else: "bg-red-500")]}/>
            <span class="text-sm text-gray-600">
              <%= if @api_status == :ok, do: "API Online", else: "API Offline" %>
            </span>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-12 w-full max-w-4xl mx-auto items-stretch mb-20">
        <.card title="Faturamento" value={@sale} subtitle="Venda Bruta" class="" icon_bg="bg-green-50">
          <:icon>
            <svg class="w-6 h-6 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 1.343-3 3s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3zm0 0V4m0 16v-4"/></svg>
          </:icon>
        </.card>
        <.card title="Custo" value={@cost} subtitle="Custo Total" class="" icon_bg="bg-blue-50">
          <:icon>
            <svg class="w-6 h-6 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3"/></svg>
          </:icon>
        </.card>
        <.card title="Devoluções" value={@devolution} subtitle="Total Devolvido" class="" icon_bg="bg-red-50">
          <:icon>
            <svg class="w-6 h-6 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/></svg>
          </:icon>
        </.card>
        <.card title="Objetivo" value={@objetivo} subtitle="Meta do Período" class="" icon_bg="bg-yellow-50">
          <:icon>
            <svg class="w-6 h-6 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a5 5 0 00-10 0v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2z"/></svg>
          </:icon>
        </.card>
        <.card title="Lucro (%)" value={@profit} subtitle="Margem Bruta" class="" icon_bg="bg-green-100">
          <:icon>
            <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 1.343-3 3s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3zm0 0V4m0 16v-4"/></svg>
          </:icon>
        </.card>

        <.card title="NFS" value={@nfs} subtitle="Notas Fiscais" class="" icon_bg="bg-yellow-100">
          <:icon>
            <svg class="w-6 h-6 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h8"/></svg>
          </:icon>
        </.card>
        <%= for _ <- 1..rem(3 - rem(6, 3), 3) do %>
          <div class="invisible"></div>
        <% end %>
      </div>

      <div class="w-full max-w-xs mx-auto mt-8 relative">
        <canvas
          id="gauge-chart"
          phx-hook="GaugeChart"
          phx-update="ignore"
          data-value={@percentual_num}
          class="w-full h-full"
        >
        </canvas>
        <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
            <span class="text-3xl font-bold text-gray-700"><%= @percentual %></span>
            <span class="text-sm font-medium text-gray-500">Meta: <%= @objetivo %></span>
        </div>
      </div>

      <div id="echarts-demo" style="width: 400px; height: 400px;"></div>
      <script type="module" src="/assets/echarts_test.js"></script>

    </div>
    """
  end
end
