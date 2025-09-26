defmodule AppWeb.OrderSearchLive do
  use AppWeb, :live_view

  @doc """
  Mounts the LiveView and initializes the order search interface.
  Loads user authentication state and recent order history with tags.
  """
  @impl true
  def mount(_params, session, socket) do
    user_token = session["user_token"]
    {current_user, recent_orders} = load_user_and_history(user_token)
    orders_with_tags = enrich_orders_with_tags(current_user, recent_orders)

    # Safely get active rooms with fallback
    active_rooms = safely_get_active_rooms()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(App.PubSub, "active_rooms")
    end

    {:ok, assign(socket,
      order_id: "",
      error: nil,
      token: user_token,
      user_object: current_user,
      order_history: orders_with_tags,
      active_rooms: active_rooms,
      search_focused: false,
      loading: false
    )}
  end

  @impl true
  def handle_event("search", %{"order_id" => order_id}, socket) do
    socket = assign(socket, :loading, true)

    case App.Orders.get_order(order_id) do
      {:ok, _order} ->
        {:noreply, push_navigate(socket, to: "/chat/#{order_id}")}
      {:error, _reason} ->
        {:noreply, assign(socket,
          error: "Pedido não encontrado",
          order_id: order_id,
          loading: false
        )}
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  @impl true
  def handle_info({:room_updated, _room_key, _room_data}, socket) do
    active_rooms = safely_get_active_rooms()
    {:noreply, assign(socket, :active_rooms, active_rooms)}
  end

  @impl true
  def handle_info({:room_removed, _room_key}, socket) do
    active_rooms = safely_get_active_rooms()
    {:noreply, assign(socket, :active_rooms, active_rooms)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-white to-indigo-50">
      <!-- Header com gradiente -->
              <div class="bg-gradient-to-r from-blue-800 to-indigo-900 text-white">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="text-center">
            <h1 class="text-4xl font-bold mb-2">JuruConnect</h1>
            <p class="text-blue-100 text-lg">Sistema de Chat por Pedido</p>

            <%= if @token do %>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Conteúdo Principal -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-8">

          <!-- Seção de Busca (2/4 da largura) -->
          <div class="lg:col-span-2">
            <div class="bg-white rounded-2xl shadow-xl border border-gray-100 p-8">
              <div class="text-center mb-8">
                <div class="inline-flex items-center justify-center w-16 h-16 bg-blue-100 rounded-full mb-4">
                  <svg class="w-8 h-8 text-blue-800" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                  </svg>
                </div>
                <h2 class="text-3xl font-bold text-gray-900 mb-2">Buscar Pedido</h2>
                <p class="text-gray-600">Digite o número do pedido para acessar o chat</p>
              </div>

              <form phx-submit="search" class="space-y-6">
                <div class="relative">
                  <label for="order_id" class="block text-sm font-semibold text-gray-700 mb-3">
                    Número do Pedido
                  </label>
                  <div class="relative">
                    <input
                      id="order_id"
                      name="order_id"
                      value={@order_id}
                      placeholder="Ex: 309036036"
                      class="w-full px-6 py-4 text-lg border-2 border-gray-200 rounded-xl transition-all duration-300 focus:outline-none focus:ring-4 focus:border-blue-500 ring-blue-100"
                      required
                    />
                    <div class="absolute inset-y-0 right-0 flex items-center pr-4">
                      <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </div>
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={@loading}
                  class="w-full bg-gradient-to-r from-blue-800 to-indigo-800 text-white py-4 px-8 rounded-xl font-semibold text-lg hover:from-blue-900 hover:to-indigo-900 focus:ring-4 focus:ring-blue-300 transition-all duration-300 shadow-lg hover:shadow-xl transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
                >
                  <%= if @loading do %>
                    <div class="flex items-center justify-center">
                      <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Buscando...
                    </div>
                  <% else %>
                    Buscar Pedido
                  <% end %>
                </button>
              </form>

              <%= if @error do %>
                <div class="mt-6 p-4 bg-red-50 border border-red-200 rounded-xl">
                  <div class="flex items-center">
                    <svg class="w-5 h-5 text-red-400 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <div class="flex-1">
                      <p class="text-red-700 font-medium"><%= @error %></p>
                    </div>
                    <button phx-click="clear_error" class="text-red-400 hover:text-red-600">
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                      </svg>
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Seção de Salas Ativas (1/4 da largura) -->
          <div class="lg:col-span-1">
            <div class="bg-white rounded-2xl shadow-xl border border-gray-100 p-6 h-fit">
              <div class="flex items-center mb-6">
                <div class="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center mr-3">
                  <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                  </svg>
                </div>
                <h3 class="text-xl font-bold text-gray-900">Salas Ativas</h3>
              </div>

              <%= if @active_rooms && length(@active_rooms) > 0 do %>
                <div class="space-y-3">
                  <%= for room <- @active_rooms do %>
                    <div class="group bg-green-50 hover:bg-green-100 p-4 rounded-xl border border-green-200 hover:border-green-300 transition-all duration-300 cursor-pointer">
                      <a href={"/chat/#{room.order_id}"} class="block">
                        <div class="flex items-center justify-between">
                          <div class="flex-1">
                            <div class="flex items-center mb-2">
                              <h4 class="font-semibold text-gray-900 group-hover:text-green-800 transition-colors">
                                Pedido <%= room.order_id %>
                              </h4>
                              <div class="ml-2 flex items-center">
                                <div class="w-2 h-2 bg-green-500 rounded-full animate-pulse mr-1"></div>
                                <span class="text-xs text-green-600 font-medium">
                                  <%= room.user_count %> online
                                </span>
                              </div>
                            </div>

                            <!-- Lista de usuários online -->
                            <div class="text-xs text-gray-600 mb-1">
                              <%= for {_user_id, user} <- room.users do %>
                                <span class="inline-block bg-white px-2 py-1 rounded-md mr-1 mb-1 text-xs">
                                  <%= user.name %>
                                </span>
                              <% end %>
                            </div>

                            <p class="text-xs text-gray-500">
                              Ativo <%= format_relative_time(room.last_activity) %>
                            </p>
                          </div>
                          <div class="text-green-600 group-hover:text-green-800 transition-colors">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                            </svg>
                          </div>
                        </div>
                      </a>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="text-center py-8">
                  <div class="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                    </svg>
                  </div>
                  <p class="text-gray-500 text-sm">Nenhuma sala ativa no momento</p>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Seção de Histórico (1/4 da largura) -->
          <div class="lg:col-span-1">
            <div class="bg-white rounded-2xl shadow-xl border border-gray-100 p-6 h-fit">
              <div class="flex items-center mb-6">
                <div class="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center mr-3">
                  <svg class="w-5 h-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                </div>
                <h3 class="text-xl font-bold text-gray-900">Histórico Recente</h3>
              </div>

              <%= if @user_object && @order_history && length(@order_history) > 0 do %>
                <div class="space-y-3">
                  <%= for history_item <- @order_history do %>
                    <div class="group bg-gray-50 hover:bg-blue-50 p-4 rounded-xl border border-gray-200 hover:border-blue-300 transition-all duration-300 cursor-pointer">
                      <a href={"/chat/#{history_item.order_id}"} class="block">
                        <div class="flex items-center justify-between">
                          <div class="flex-1">
                            <div class="flex items-center mb-2">
                              <h4 class="font-semibold text-gray-900 group-hover:text-blue-800 transition-colors">
                                Pedido <%= history_item.order_id %>
                              </h4>
                              <%= if history_item.access_count > 1 do %>
                                <span class="ml-2 px-2 py-1 bg-blue-100 text-blue-700 text-xs rounded-full">
                                  <%= history_item.access_count %>x
                                </span>
                              <% end %>
                            </div>

                            <!-- Tags do Pedido -->
                            <%= if history_item.tags && length(history_item.tags) > 0 do %>
                              <div class="flex flex-wrap gap-1 mb-2">
                                <%= for tag <- history_item.tags do %>
                                  <div class="flex items-center bg-white border border-slate-200 rounded-lg px-2 py-1 shadow-sm">
                                    <div class="w-2 h-2 rounded-full mr-1.5" style={"background-color: #{tag.color}"}></div>
                                    <span class="text-xs font-medium text-slate-700"><%= tag.name %></span>
                                  </div>
                                <% end %>
                              </div>
                            <% end %>

                            <p class="text-sm text-gray-600">
                              Acessado <%= format_relative_time(history_item.last_accessed_at) %>
                            </p>
                          </div>
                          <div class="text-blue-600 group-hover:text-blue-800 transition-colors">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                            </svg>
                          </div>
                        </div>
                      </a>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="text-center py-8">
                  <div class="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                    </svg>
                  </div>
                  <p class="text-gray-500 text-sm">
                    <%= if @user_object do %>
                      Nenhum pedido acessado ainda
                    <% else %>
                      Faça login para ver seu histórico
                    <% end %>
                  </p>
                </div>
              <% end %>
            </div>
          </div>
        </div>

          <!-- Informações adicionais -->
          <div class="mt-8 text-center">

        </div>
      </div>
    </div>
    """
  end

  defp load_user_and_history(nil), do: {nil, []}
  defp load_user_and_history(user_token) do
    case AppWeb.Auth.Guardian.resource_from_token(user_token) do
      {:ok, user, _claims} ->
        recent_orders = App.Accounts.get_user_order_history(user.id, 5)
        {user, recent_orders}
      {:error, _reason} ->
        {nil, []}
    end
  end

  defp enrich_orders_with_tags(nil, _orders), do: []
  defp enrich_orders_with_tags(_user, []), do: []
  defp enrich_orders_with_tags(_user, orders) do
    Enum.map(orders, fn order ->
      tags = App.Tags.get_treaty_tags(order.order_id)
      Map.put(order, :tags, tags)
    end)
  end

  defp format_relative_time(datetime) do
    now = App.DateTimeHelper.now()
    seconds_ago = DateTime.diff(now, datetime, :second)

    cond do
      seconds_ago < 60 -> "há alguns segundos"
      seconds_ago < 3600 -> format_minutes(seconds_ago)
      seconds_ago < 86400 -> format_hours(seconds_ago)
      seconds_ago < 2592000 -> format_days(seconds_ago)
      true -> "há mais de um mês"
    end
  end

  defp format_minutes(seconds_ago) do
    minutes = div(seconds_ago, 60)
    "há #{minutes} minuto#{pluralize(minutes)}"
  end

  defp format_hours(seconds_ago) do
    hours = div(seconds_ago, 3600)
    "há #{hours} hora#{pluralize(hours)}"
  end

  defp format_days(seconds_ago) do
    days = div(seconds_ago, 86400)
    "há #{days} dia#{pluralize(days)}"
  end

  defp pluralize(1), do: ""
  defp pluralize(_), do: "s"

  # Private helper functions

  defp safely_get_active_rooms do
    case Process.whereis(App.ActiveRooms) do
      nil ->
        []
      _pid ->
        safely_call_active_rooms()
    end
  end

  defp safely_call_active_rooms do
    try do
      App.ActiveRooms.list_active_rooms()
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end
end
