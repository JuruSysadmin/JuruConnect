defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view

  alias AppWeb.Auth.Guardian

  @impl true
  def mount(_params, session, socket) do
    user =
      with token when not is_nil(token) <- session["guardian_default_token"],
           {:ok, claims} <- Guardian.decode_and_verify(token),
           {:ok, user} <- Guardian.resource_from_claims(claims) do
        user
      else
        _ -> nil
      end

    if connected?(socket), do: :timer.send_interval(1000, self(), :tick)

    {:ok,
     assign(socket,
       current_user: user,
       faturamento: 754_644.72,
       realizado: 92.48,
       margem: 22.01,
       cupons: 1970,
       ticket: 383.07,
       tick: 0,
       activities: [
         %{type: :meta, loja: "Alcindo", percent: 60},
         %{type: :meta, loja: "BR", percent: 20},
         %{type: :meta, loja: "Senador", percent: 45},
         %{type: :meta, loja: "Castanhal", percent: 80},
         %{type: :venda, user: "Yasmin", valor: 27_000},
         %{type: :produto, marca: "CORAL"}
       ]
     )}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Simula pequenas variações nos dados
    socket =
      socket
      |> update(:faturamento, &(&1 + :rand.uniform(1000) - 500))
      |> update(:realizado, &max(0.0, min(100.0, &1 + (:rand.uniform(10) - 5) / 10)))
      |> update(:margem, &max(0.0, min(40.0, &1 + (:rand.uniform(10) - 5) / 10)))
      |> update(:cupons, &(&1 + :rand.uniform(10) - 5))
      |> update(:ticket, &max(0.0, &1 + (:rand.uniform(10) - 5) / 10))
      |> update(:tick, &(&1 + 1))
      # Exemplo: embaralha a ordem das atividades para simular dinamismo
      |> update(:activities, &Enum.shuffle/1)

    {:noreply, socket}
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
          <%= if @current_user do %>
            <div class="mt-4 flex items-center space-x-2">
              <div class="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center font-bold text-blue-700">
                {String.first(@current_user.username)}
              </div>
              <div>
                <div class="text-sm font-semibold text-gray-900">{@current_user.username}</div>
                <div class="text-xs text-gray-500">{@current_user.username}</div>
              </div>
            </div>
          <% end %>
        </div>
        <!-- User Profile -->
        <%= if @current_user do %>
          <div class="p-4 border-b border-gray-100">
            <div class="flex items-center space-x-2">
              <div class="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center font-bold text-blue-700">
                {String.first(@current_user.username)}
              </div>
              <div>
                <div class="text-sm font-semibold text-gray-900">{@current_user.username}</div>
                <div class="text-xs text-gray-500">{@current_user.username}</div>
              </div>
            </div>
          </div>
        <% end %>
        <!-- Navigation -->
        <nav class="flex-1 p-4 space-y-1">
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 5a2 2 0 012-2h4a2 2 0 012 2v6H8V5z"
              />
            </svg>
            Dashboard
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
            Forms
            <span class="ml-auto bg-gray-200 text-gray-700 text-xs px-2 py-1 rounded-full">12</span>
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
              />
            </svg>
            Submissions
            <span class="ml-auto bg-red-100 text-red-700 text-xs px-2 py-1 rounded-full">3</span>
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
              />
            </svg>
            Analytics
          </a>
          <div class="border-t border-gray-200 my-4"></div>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
              />
            </svg>
            Team
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            Settings
          </a>
          <a
            href="#"
            class="flex items-center px-3 py-2 text-sm font-medium text-gray-700 rounded-lg hover:bg-gray-100 group"
          >
            <svg class="w-5 h-5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            Help & Support
          </a>
        </nav>
      </div>
      <!-- Main Content Area -->
      <div class="flex-1 ml-64 flex flex-col items-center py-12 px-4 sm:px-8 bg-white">
        <h1 class="text-4xl font-extrabold text-gray-900 mb-4 text-center tracking-tight">
          Dashboard
        </h1>
        <%= if @current_user do %>
          <div class="text-lg font-bold text-center mb-8">Bem-vindo, {@current_user.username}!</div>
        <% end %>
        <!-- Cards: Grid responsiva, centralizada, espaçamento amplo -->
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-2 xl:grid-cols-4 gap-8 w-full max-w-6xl mx-auto items-stretch mb-12">
          <!-- Card 2: Realizado -->
          <div class="bg-white rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-4 md:p-8 w-full min-w-[180px] max-w-xs">
            <div class="flex items-center mb-2">
              <div class="w-10 h-10 rounded-full bg-blue-50 flex items-center justify-center mr-2">
                <svg
                  class="w-6 h-6 text-blue-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3"
                  />
                </svg>
              </div>
              <span class="text-lg font-semibold text-gray-700">Realizado</span>
            </div>
            <div class="text-3xl font-extrabold text-gray-900 mb-1 w-full text-center">
              {Float.round(:erlang.float(@realizado), 2)}%
            </div>
            <div class="text-xs text-gray-400">Meta</div>
          </div>
          <!-- Card 3: Margem Líquida -->
          <div class="bg-white rounded-2xl shadow-lg border border-gray-100 flex flex-col items-center justify-center p-4 md:p-8 w-full min-w-[180px] max-w-xs">
            <div class="flex items-center mb-2">
              <div class="w-10 h-10 rounded-full bg-yellow-50 flex items-center justify-center mr-2">
                <svg
                  class="w-6 h-6 text-yellow-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17 9V7a5 5 0 00-10 0v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2z"
                  />
                </svg>
              </div>
              <span class="text-lg font-semibold text-gray-700">Margem</span>
            </div>
            <div class="text-3xl font-extrabold text-gray-900 mb-1 w-full text-center">
              {Float.round(:erlang.float(@margem), 2)}%
            </div>
            <div class="text-xs text-gray-400">Líquida</div>
          </div>
        </div>
        <!-- Metas & Atividades -->
        <div class="bg-white rounded-xl shadow-lg border border-gray-100 w-auto max-w-6xl">
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
                    <span class="ml-1">{percent}% atingida</span>
                  </div>
                <% %{type: :venda, user: user, valor: valor} -> %>
                  <div class="flex items-center text-sm text-green-700">
                    <span class="font-bold mr-2">Venda</span>
                    <span>{user} vendeu</span>
                    <span class="font-semibold ml-1">
                      R$ {:erlang.float_to_binary(:erlang.float(valor), decimals: 2)}
                    </span>
                  </div>
                <% %{type: :produto, marca: marca} -> %>
                  <div class="flex items-center text-sm text-yellow-700">
                    <span class="font-bold mr-2">Produto em Alta</span>
                    <span>Marca <span class="font-semibold ml-1">{marca}</span></span>
                  </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
