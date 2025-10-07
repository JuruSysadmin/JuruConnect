defmodule AppWeb.TreatySearchLive do
  use AppWeb, :live_view

  @doc """
  Mounts the LiveView and initializes the treaty search interface.
  Loads user authentication state and recent treaty history with tags.
  """
  @impl true
  def mount(_params, session, socket) do
    try do
      user_token = session["user_token"]
      {current_user, recent_treaties} = load_user_and_history(user_token)
      treaties_with_tags = enrich_treaties_with_tags(current_user, recent_treaties)

      active_rooms = safely_get_active_rooms()

      {notifications, unread_count} = safely_load_user_notifications(current_user)

      summary_stats = if current_user && current_user.role == "admin" do
        safely_get_summary_stats(current_user.id)
      else
        nil
      end

      if connected?(socket) do
        Phoenix.PubSub.subscribe(App.PubSub, "active_rooms")
        if current_user do
          Phoenix.PubSub.subscribe(App.PubSub, "user:#{current_user.id}")
        end
      end

      {:ok, assign(socket,
        treaty_id: "",
        error: nil,
        token: user_token,
        user_object: current_user,
        treaty_history: treaties_with_tags,
        active_rooms: active_rooms,
        search_focused: false,
        loading: false,
        active_tab: "create",
        notifications: notifications,
        unread_notification_count: unread_count,
        show_notifications: false,
        summary_stats: summary_stats
      )}
    rescue
      _error ->
        # Socket básico em caso de erro
        {:ok, assign(socket,
          treaty_id: "",
          error: nil,
          token: session["user_token"] || nil,
          user_object: nil,
          treaty_history: [],
          active_rooms: [],
          search_focused: false,
          loading: false,
          active_tab: "create",
          notifications: [],
          unread_notification_count: 0,
          show_notifications: false,
          summary_stats: nil
        )}
    end
  end

  @impl true
  def handle_event("search", %{"treaty_id" => treaty_id}, socket) do

    socket = assign(socket, :loading, true)

    case App.Treaties.get_treaty(treaty_id) do
      {:ok, _treaty} ->
        {:noreply, push_navigate(socket, to: "/chat/#{treaty_id}")}
      {:error, _reason} ->
        {:noreply, assign(socket,
          error: "Tratativa não encontrada. Crie uma nova tratativa abaixo.",
          treaty_id: treaty_id,
          loading: false
        )}
    end
  end

  @impl true
  def handle_event("create_treaty", %{"title" => title, "description" => description, "category" => category}, socket) do
    socket = assign(socket, :loading, true)

    case socket.assigns.user_object do
      nil ->
        {:noreply, assign(socket,
          error: "Você precisa estar logado para criar tratativas",
          loading: false
        )}

      user ->
        treaty_attrs = %{
          title: title,
          description: description,
          category: category,
          created_by: user.id,
          store_id: user.store_id
        }

        case App.Treaties.create_treaty(treaty_attrs) do
          {:ok, treaty} ->
            {:noreply, push_navigate(socket, to: "/chat/#{treaty.treaty_code}")}
          {:error, changeset} ->
            error_message = extract_treaty_creation_error(changeset)
            {:noreply, assign(socket, error: error_message, loading: false)}
        end
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("clear_history", _params, socket) do
    case socket.assigns.user_object do
      nil ->
        {:noreply, socket}

      user ->
        App.Accounts.clear_user_order_history(user.id)

        {:noreply, assign(socket, :treaty_history, [])}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply, push_navigate(socket, to: "/logout")}
  end

  @impl true
  def handle_event("toggle_notifications", _params, socket) do
    {:noreply, assign(socket, :show_notifications, !socket.assigns.show_notifications)}
  end

  @impl true
  def handle_event("mark_notification_read", %{"id" => notification_id}, socket) do
    case socket.assigns.user_object do
      nil ->
        {:noreply, socket}
      user ->
        case App.Notifications.mark_notifications_as_read(user.id, notification_id) do
          {:ok, _count} ->
            {notifications, unread_count} = load_user_notifications(user)
            {:noreply, assign(socket,
              notifications: notifications,
              unread_notification_count: unread_count
            )}
          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("mark_all_notifications_read", _params, socket) do
    case socket.assigns.user_object do
      nil ->
        {:noreply, socket}
      user ->
        case App.Notifications.mark_all_notifications_as_read(user.id) do
          {:ok, _count} ->
            {notifications, unread_count} = load_user_notifications(user)
            {:noreply, assign(socket,
              notifications: notifications,
              unread_notification_count: unread_count
            )}
          {:error, _reason} ->
            {:noreply, socket}
        end
    end
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
  def handle_info({:notification, _type, _notification_data}, socket) do
    try do
      case socket.assigns.user_object do
        nil ->
          {:noreply, socket}
        user ->
          {notifications, unread_count} = safely_load_user_notifications(user)
          {:noreply, assign(socket,
            notifications: notifications,
            unread_notification_count: unread_count
          )}
      end
    rescue
      _error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:desktop_notification, _notification_data}, socket) do
    try do
      case socket.assigns.user_object do
        nil ->
          {:noreply, socket}
        user ->
          {notifications, unread_count} = safely_load_user_notifications(user)
          {:noreply, assign(socket,
            notifications: notifications,
            unread_notification_count: unread_count
          )}
      end
    rescue
      _error ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header Enterprise -->
      <header class="bg-white border-b border-gray-200 shadow-sm">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
                  <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                  </svg>
                </div>
              </div>
              <div class="ml-4">
                <h1 class="text-xl font-semibold text-gray-900">JuruConnect</h1>
                <p class="text-sm text-gray-500">Resolução de Tratativas</p>
              </div>
            </div>
            <%= if @token do %>
              <div class="flex items-center space-x-4">
                <!-- Notification Bell -->
                <%= if @user_object do %>
                  <div class="relative">
                    <button
                      phx-click="toggle_notifications"
                      class="relative p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
                      title="Notificações"
                    >
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-5 5v-5zM4.828 7l2.586 2.586a2 2 0 001.414.586H20a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V9a2 2 0 012-2h.828z"></path>
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4"></path>
                      </svg>
                      <%= if @unread_notification_count > 0 do %>
                        <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full h-5 w-5 flex items-center justify-center font-medium">
                          <%= if @unread_notification_count > 9, do: "9+", else: @unread_notification_count %>
                        </span>
                      <% end %>
                    </button>
                  </div>


                  <div class="relative">
                    <!-- Notification Dropdown -->
                    <%= if @show_notifications do %>
                      <div class="absolute right-0 mt-2 w-72 sm:w-80 bg-white rounded-lg shadow-lg border border-gray-200 z-50">
                        <div class="p-4 border-b border-gray-200">
                          <div class="flex items-center justify-between">
                            <h3 class="text-lg font-semibold text-gray-900">Notificações</h3>
                            <%= if @unread_notification_count > 0 do %>
                              <button
                                phx-click="mark_all_notifications_read"
                                class="text-sm text-blue-600 hover:text-blue-800"
                              >
                                Marcar todas como lidas
                              </button>
                            <% end %>
                          </div>
                        </div>
                        <div class="max-h-96 overflow-y-auto">
                          <%= if @notifications && length(@notifications) > 0 do %>
                            <div class="divide-y divide-gray-200">
                              <%= for notification <- @notifications do %>
                                <div class={"p-4 hover:bg-gray-50 cursor-pointer #{if !notification.is_read, do: "bg-blue-50"}"}>
                                  <div class="flex items-start space-x-3">
                                    <div class="flex-shrink-0">
                                      <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                                        <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                                        </svg>
                                      </div>
                                    </div>
                                    <div class="flex-1 min-w-0">
                                      <div class="flex items-center justify-between">
                                        <p class="text-sm font-medium text-gray-900 truncate">
                                          <%= notification.title %>
                                        </p>
                                        <%= if !notification.is_read do %>
                                          <div class="w-2 h-2 bg-blue-500 rounded-full flex-shrink-0 ml-2"></div>
                                        <% end %>
                                      </div>
                                      <p class="text-sm text-gray-500 mt-1 line-clamp-2">
                                        <%= notification.body %>
                                      </p>
                                      <p class="text-xs text-gray-400 mt-1">
                                        <%= format_relative_time(notification.inserted_at) %>
                                      </p>
                                      <%= if notification.treaty_id do %>
                                        <div class="mt-2">
                                          <a
                                            href={"/chat/#{get_treaty_code_from_notification(notification)}"}
                                            phx-click="mark_notification_read"
                                            phx-value-id={notification.id}
                                            class="text-xs text-blue-600 hover:text-blue-800"
                                          >
                                            Ver conversa →
                                          </a>
                                        </div>
                                      <% end %>
                                    </div>
                                  </div>
                                </div>
                              <% end %>
                            </div>
                          <% else %>
                            <div class="p-8 text-center">
                              <div class="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                                <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-5 5v-5zM4.828 7l2.586 2.586a2 2 0 001.414.586H20a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V9a2 2 0 012-2h.828z"></path>
                                </svg>
                              </div>
                              <p class="text-sm text-gray-500">Nenhuma notificação</p>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <div class="flex items-center space-x-4">
                  <div class="text-sm text-gray-600">
                    Bem-vindo, <%= if @user_object, do: @user_object.name, else: "Usuário" %>
                  </div>
                  <button
                    phx-click="logout"
                    class="inline-flex items-center px-2 py-1 text-xs text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded transition-colors"
                    title="Sair"
                  >
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path>
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </header>

      <!-- Conteúdo Principal -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <!-- Breadcrumb -->
        <nav class="mb-6">
          <ol class="flex items-center space-x-2 text-sm text-gray-500">
            <li>
              <a href="/" class="hover:text-gray-700">Início</a>
            </li>
            <li class="flex items-center">
              <svg class="w-4 h-4 mx-2" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd"></path>
              </svg>
              <span class="text-gray-900 font-medium">Tratativas</span>
            </li>
          </ol>
        </nav>

        <!-- User Summary Cards -->
        <%= if @summary_stats do %>
          <div class="mb-8">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-gray-900">Minhas Tratativas</h2>
              <a
                href="/admin/dashboard"
                class="text-sm text-purple-600 hover:text-purple-800 font-medium"
              >
                Ver dashboard completo →
              </a>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
              <!-- Total Tratativas -->
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                      <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Total</p>
                    <p class="text-lg font-semibold text-gray-900"><%= @summary_stats.user_total_treaties %></p>
                  </div>
                </div>
              </div>

              <!-- Tratativas Ativas -->
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                      <svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Ativas</p>
                    <p class="text-lg font-semibold text-gray-900"><%= @summary_stats.user_active_treaties %></p>
                  </div>
                </div>
              </div>

              <!-- Tratativas Encerradas -->
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-red-100 rounded-lg flex items-center justify-center">
                      <svg class="w-4 h-4 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Encerradas</p>
                    <p class="text-lg font-semibold text-gray-900"><%= @summary_stats.user_closed_treaties %></p>
                  </div>
                </div>
              </div>

              <!-- Taxa de Reabertura -->
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-yellow-100 rounded-lg flex items-center justify-center">
                      <svg class="w-4 h-4 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                      </svg>
                    </div>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Reabertura</p>
                    <p class="text-lg font-semibold text-gray-900"><%= @summary_stats.user_reopen_rate %>%</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Grid Responsivo -->
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <!-- Seção Principal - Responsiva -->
          <div class="lg:col-span-8">
            <div class="bg-white rounded-lg shadow-sm border border-gray-200">
              <div class="px-4 sm:px-6 py-4 border-b border-gray-200">
                <h2 class="text-lg font-semibold text-gray-900">Gerenciar Tratativas</h2>
                <p class="text-sm text-gray-600 mt-1">Busque uma tratativa existente ou crie uma nova</p>
              </div>
              <div class="p-4 sm:p-6">

                <!-- Tabs para alternar entre criar e buscar -->
                <div class="border-b border-gray-200 mb-6">
                  <nav class="-mb-px flex space-x-8">
                    <button type="button" class={"py-2 px-1 border-b-2 font-medium text-sm transition-colors #{if @active_tab == "create", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"}"} phx-click="set_tab" phx-value-tab="create">
                      Criar Nova
                    </button>
                    <button type="button" class={"py-2 px-1 border-b-2 font-medium text-sm transition-colors #{if @active_tab == "search", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"}"} phx-click="set_tab" phx-value-tab="search">
                      Buscar Existente
                    </button>
                  </nav>
                </div>

                <!-- Formulário de Criação -->
                <div class={"space-y-6 #{if @active_tab != "create", do: "hidden"}"}>
                  <form phx-submit="create_treaty" class="space-y-6">
                    <div class="space-y-2">
                      <label for="treaty_title" class="block text-sm font-medium text-gray-700">
                        Título da Tratativa *
                      </label>
                      <input
                        id="treaty_title"
                        name="title"
                        placeholder="Ex: Negociação de Contrato"
                        class="w-full px-4 py-3 border border-gray-300 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-sm placeholder-gray-400 transition-all"
                        required
                      />
                    </div>

                    <div class="space-y-2">
                      <label for="treaty_description" class="block text-sm font-medium text-gray-700">
                        Descrição *
                          </label>
                      <textarea
                        id="treaty_description"
                        name="description"
                        rows="4"
                        placeholder="Descreva os detalhes da tratativa..."
                        class="w-full px-4 py-3 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-sm resize-none transition-all"
                        required
                      ></textarea>
                    </div>

                    <div class="space-y-2">
                      <label for="treaty_category" class="block text-sm font-medium text-gray-700">
                        Categoria *
                      </label>
                      <select
                        id="treaty_category"
                        name="category"
                        class="w-full px-4 py-3 border border-gray-300 rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-sm transition-all"
                        required
                      >
                        <option value="COMERCIAL">Comercial</option>
                        <option value="FINANCEIRO">Financeiro</option>
                        <option value="LOGISTICA">Logística</option>
                      </select>
                    </div>

                    <div class="flex justify-end pt-6">
                      <button
                        type="submit"
                        disabled={@loading}
                        class="inline-flex items-center px-8 py-3 border border-transparent text-sm font-bold rounded-xl shadow-lg text-white bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 group"
                      >
                        <%= if @loading do %>
                          <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2-647z"></path>
                          </svg>
                          Criando...
                        <% else %>
                          <svg class="w-5 h-5 mr-3 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" pointLinecap="round" stroke-linejoin="round" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                          </svg>
                          Criar Tratativa
                        <% end %>
                      </button>
                    </div>
                  </form>
                </div>

                <!-- Formulário de Busca -->
                <div class={"space-y-8 #{if @active_tab != "search", do: "hidden"}"}>
                  <form phx-submit="search" class="space-y-8">
                    <div class="space-y-3">
                      <label for="treaty_id" class="block text-sm font-bold text-gray-800">
                        Código da Tratativa *
                      </label>
                      <div class="relative">
                        <input
                          id="treaty_id"
                          name="treaty_id"
                          value={@treaty_id}
                          placeholder="Ex: TRT001234"
                          class="w-full px-4 py-3 pl-12 border border-gray-200 rounded-xl shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-sm placeholder-gray-400 bg-white/50 backdrop-blur-sm transition-all"
                          required
                        />
                        <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                          <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                          </svg>
                        </div>
                      </div>
                    </div>

                    <div class="flex justify-end pt-6">
                      <button
                        type="submit"
                        disabled={@loading}
                        class="inline-flex items-center px-8 py-3 border border-transparent text-sm font-bold rounded-xl shadow-lg text-white bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 group"
                      >
                        <%= if @loading do %>
                          <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2-647z"></path>
                          </svg>
                          Buscando...
                        <% else %>
                          <svg class="w-5 h-5 mr-3 group-hover:scale-110 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
                          </svg>
                          Buscar Tratativa
                        <% end %>
                      </button>
                    </div>
                  </form>
                </div>

                <%= if @error do %>
                  <div class="mt-6 p-4 bg-red-50 border border-red-200 rounded-md">
                    <div class="flex items-start">
                      <div class="flex-shrink-0">
                        <svg class="h-5 w-5 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                      </div>
                      <div class="ml-3 flex-1">
                        <p class="text-sm text-red-700"><%= @error %></p>
                      </div>
                      <div class="ml-3 flex-shrink-0">
                        <button phx-click="clear_error" class="text-red-400 hover:text-red-600 transition-colors">
                          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                          </svg>
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Sidebar - Responsiva -->
          <div class="lg:col-span-4 space-y-6">
            <!-- Salas Ativas -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200">
              <div class="px-4 sm:px-6 py-4 border-b border-gray-200">
                <div class="flex items-center">
                  <div class="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center mr-3">
                    <svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                    </svg>
                  </div>
                  <h3 class="text-lg font-semibold text-gray-900">Salas Ativas</h3>
                </div>
              </div>
              <div class="p-4 sm:p-6">
                <%= if @active_rooms && length(@active_rooms) > 0 do %>
                  <div class="space-y-3">
                    <%= for room <- @active_rooms do %>
                      <div class="group bg-gray-50 hover:bg-green-50 p-3 rounded-lg border border-gray-200 hover:border-green-300 transition-all duration-200 cursor-pointer">
                        <a href={"/chat/#{room.treaty_id}"} class="block">
                          <div class="flex items-center justify-between">
                            <div class="flex-1 min-w-0">
                              <div class="flex items-center mb-1">
                                <h4 class="text-sm font-medium text-gray-900 truncate group-hover:text-green-800">
                                  <%= room.treaty_id %>
                                </h4>
                                <div class="ml-2 flex items-center">
                                  <div class="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse mr-1"></div>
                                  <span class="text-xs text-green-600 font-medium">
                                    <%= room.user_count %>
                                  </span>
                                </div>
                              </div>
                              <p class="text-xs text-gray-500 truncate">
                                <%= format_relative_time(room.last_activity) %>
                              </p>
                            </div>
                            <div class="text-gray-400 group-hover:text-green-600 transition-colors ml-2">
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                              </svg>
                            </div>
                          </div>
                        </a>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <div class="text-center py-6">
                    <div class="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                      <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
                      </svg>
                    </div>
                    <p class="text-sm text-gray-500">Nenhuma sala ativa</p>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Histórico Recente -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200">
              <div class="px-4 sm:px-6 py-4 border-b border-gray-200">
                <div class="flex items-center justify-between">
                  <div class="flex items-center">
                    <div class="w-8 h-8 bg-indigo-100 rounded-lg flex items-center justify-center mr-3">
                      <svg class="w-4 h-4 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                      </svg>
                    </div>
                    <h3 class="text-lg font-semibold text-gray-900">Histórico</h3>
                  </div>
                  <%= if @user_object && @treaty_history && length(@treaty_history) > 0 do %>
                    <button
                      phx-click="clear_history"
                      class="text-gray-400 hover:text-red-600 transition-colors"
                      title="Limpar histórico"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                      </svg>
                    </button>
                  <% end %>
                </div>
              </div>
              <div class="p-4 sm:p-6">
                <%= if @user_object && @treaty_history && length(@treaty_history) > 0 do %>
                  <div class="space-y-3">
                    <%= for history_item <- @treaty_history do %>
                      <div class="group bg-gray-50 hover:bg-blue-50 p-3 rounded-lg border border-gray-200 hover:border-blue-300 transition-all duration-200 cursor-pointer">
                        <a href={"/chat/#{history_item.treaty_id}"} class="block">
                          <div class="flex items-center justify-between">
                            <div class="flex-1 min-w-0">
                              <div class="flex items-center mb-1">
                                <h4 class="text-sm font-medium text-gray-900 truncate group-hover:text-blue-800">
                                  <%= history_item.treaty_id %>
                                </h4>
                                <%= if history_item.access_count > 1 do %>
                                  <span class="ml-2 px-1.5 py-0.5 bg-blue-100 text-blue-700 text-xs rounded-full">
                                    <%= history_item.access_count %>x
                                  </span>
                                <% end %>
                              </div>
                              <p class="text-xs text-gray-500 truncate">
                                <%= format_relative_time(history_item.last_accessed_at) %>
                              </p>
                            </div>
                            <div class="text-gray-400 group-hover:text-blue-600 transition-colors ml-2">
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                              </svg>
                            </div>
                          </div>
                        </a>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <div class="text-center py-6">
                    <div class="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mx-auto mb-3">
                      <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                      </svg>
                    </div>
                    <p class="text-sm text-gray-500">
                      <%= if @user_object do %>
                        Nenhuma tratativa acessada
                      <% else %>
                        Faça login para ver histórico
                      <% end %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>

    """
  end

  defp load_user_and_history(nil), do: {nil, []}
  defp load_user_and_history(user_token) do
    case AppWeb.Auth.Guardian.resource_from_token(user_token) do
      {:ok, user, _claims} ->
        recent_treaties = App.Accounts.get_user_order_history(user.id, 5)
        {user, recent_treaties}
      {:error, _reason} ->
        {nil, []}
    end
  end

  defp enrich_treaties_with_tags(nil, _treaties), do: []
  defp enrich_treaties_with_tags(_user, []), do: []
  defp enrich_treaties_with_tags(_user, treaties) do
    Enum.map(treaties, fn treaty ->
      tags = App.Tags.get_treaty_tags(treaty.treaty_id)
      Map.put(treaty, :tags, tags)
    end)
  end

  defp format_relative_time(datetime) do
    now = App.DateTimeHelper.now()
    seconds_ago = DateTime.diff(now, datetime, :second)

    cond do
      seconds_ago < 60 -> "há alguns segundos"
      seconds_ago < 3600 -> format_minutes(seconds_ago)
      seconds_ago < 86_400 -> format_hours(seconds_ago)
      seconds_ago < 2_592_000 -> format_days(seconds_ago)
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
    days = div(seconds_ago, 86_400)
    "há #{days} dia#{pluralize(days)}"
  end

  defp pluralize(1), do: ""
  defp pluralize(_), do: "s"

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

  defp load_user_notifications(nil), do: {[], 0}
  defp load_user_notifications(user) do
    notifications = App.Notifications.get_user_notifications(user.id, 10)
    unread_count = App.Notifications.get_unread_count(user.id)
    {notifications, unread_count}
  end

  defp safely_load_user_notifications(nil), do: {[], 0}
  defp safely_load_user_notifications(user) do
    try do
      notifications = App.Notifications.get_user_notifications(user.id, 10)
      unread_count = App.Notifications.get_unread_count(user.id)
      {notifications, unread_count}
    rescue
      _error ->
        {[], 0}
    end
  end

  defp safely_get_summary_stats(user_id) do
    try do
      App.Treaties.get_user_home_summary_stats(user_id)
    rescue
      _error ->
        nil
    catch
      :exit, _ -> nil
    end
  end

  defp get_treaty_code_from_notification(notification) do
    try do
      case notification.metadata do
        %{"treaty_code" => treaty_code} when not is_nil(treaty_code) ->
          treaty_code
        %{:treaty_code => treaty_code} when not is_nil(treaty_code) ->
          treaty_code
        _ ->
          case App.Treaties.get_treaty_by_id(notification.treaty_id) do
            {:ok, treaty} -> treaty.treaty_code
            {:error, _} -> notification.treaty_id
          end
      end
    rescue
      _ -> notification.treaty_id
    end
  end

  defp extract_treaty_creation_error(changeset) do
    case changeset.errors do
      [treaty_code: {"has already been taken", _}] -> "Erro ao gerar código único. Tente novamente."
      _ -> "Erro ao criar tratativa"
    end
  end
end
