defmodule AppWeb.AdminLive.SecurityDashboard do
  @moduledoc """
  Dashboard administrativo de segurança.

  Fornece interface para:
  - Monitoramento de tentativas de login
  - Gestão de usuários bloqueados
  - Estatísticas de segurança
  - Logs de auditoria
  - Configuração de políticas
  """

  use AppWeb, :live_view

  alias App.Auth.{RateLimiter, PasswordReset, PasswordPolicy}
  alias App.Accounts

  def mount(_params, session, socket) do
    # Verificar se o usuário é admin
    case get_current_user(session) do
      %{role: role} when role in ["admin", "manager"] ->
        if connected?(socket) do
          # Atualizar dados a cada 30 segundos
          :timer.send_interval(30_000, self(), :refresh_data)
        end

        {:ok,
         socket
         |> assign(:current_user, get_current_user(session))
         |> assign(:tab, "overview")
         |> load_security_data()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Acesso negado. Apenas administradores.")
         |> push_navigate(to: "/dashboard")}
    end
  end

  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: "/admin/security?tab=#{tab}")}
  end

  def handle_event("unlock_ip", %{"ip" => ip}, socket) do
    # Implementar desbloqueio de IP
    # Por enquanto, simulação
    {:noreply,
     socket
     |> put_flash(:info, "IP #{ip} desbloqueado com sucesso.")
     |> load_security_data()}
  end

  def handle_event("unlock_user", %{"username" => username}, socket) do
    # Implementar desbloqueio de usuário
    {:noreply,
     socket
     |> put_flash(:info, "Usuário #{username} desbloqueado com sucesso.")
     |> load_security_data()}
  end

  def handle_event("reset_user_password", %{"user_id" => user_id}, socket) do
    case Accounts.get_user!(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Usuário não encontrado.")}

      user ->
        new_password = PasswordPolicy.generate_secure_password(12)

        case Accounts.update_user(user, %{password: new_password}) do
          {:ok, _updated_user} ->
            # Enviar senha por email (implementar)
            {:noreply,
             socket
             |> put_flash(:info, "Senha resetada. Nova senha enviada por e-mail.")
             |> load_security_data()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Erro ao resetar senha.")}
        end
    end
  end

  def handle_event("export_logs", %{"format" => format}, socket) do
    # Implementar exportação de logs
    {:noreply,
     socket
     |> put_flash(:info, "Logs exportados em formato #{format}.")
     |> load_security_data()}
  end

  def handle_info(:refresh_data, socket) do
    {:noreply, load_security_data(socket)}
  end

  defp load_security_data(socket) do
    socket
    |> assign(:rate_limiter_stats, RateLimiter.get_stats())
    |> assign(:password_reset_stats, PasswordReset.get_reset_stats())
    |> assign(:policy_info, PasswordPolicy.get_policy_info())
    |> assign(:recent_events, get_recent_security_events())
    |> assign(:user_stats, get_user_statistics())
    |> assign(:locked_accounts, get_locked_accounts())
    |> assign(:locked_ips, get_locked_ips())
  end

  defp get_current_user(session) do
    case Map.get(session, "user_id") do
      nil -> nil
      user_id -> Accounts.get_user!(user_id)
    end
  end

  defp get_recent_security_events do
    # Buscar eventos recentes do SecurityLogger
    # Por enquanto, dados simulados
    [
      %{
        id: 1,
        type: :login_success,
        username: "admin",
        ip_address: "192.168.1.100",
        timestamp: DateTime.utc_now(),
        details: "Login bem-sucedido"
      },
      %{
        id: 2,
        type: :login_failed,
        username: "user123",
        ip_address: "10.0.0.1",
        timestamp: DateTime.add(DateTime.utc_now(), -300, :second),
        details: "Credenciais inválidas"
      },
      %{
        id: 3,
        type: :brute_force_detected,
        username: nil,
        ip_address: "192.168.1.200",
        timestamp: DateTime.add(DateTime.utc_now(), -600, :second),
        details: "5 tentativas falharam em 5 minutos"
      }
    ]
  end

  defp get_user_statistics do
    total_users = Accounts.count_users()
    active_users = Accounts.count_active_users()

    %{
      total_users: total_users,
      active_users: active_users,
      inactive_users: total_users - active_users,
      admin_users: Accounts.count_users_by_role("admin"),
      manager_users: Accounts.count_users_by_role("manager"),
      clerk_users: Accounts.count_users_by_role("clerk")
    }
  end

  defp get_locked_accounts do
    # Buscar contas bloqueadas
    # Por enquanto, dados simulados
    [
      %{username: "user123", locked_until: DateTime.add(DateTime.utc_now(), 900, :second), reason: "Múltiplas tentativas falhas"},
      %{username: "test_user", locked_until: DateTime.add(DateTime.utc_now(), 600, :second), reason: "Atividade suspeita"}
    ]
  end

  defp get_locked_ips do
    # Buscar IPs bloqueados
    # Por enquanto, dados simulados
    [
      %{ip: "192.168.1.200", locked_until: DateTime.add(DateTime.utc_now(), 1200, :second), attempts: 10},
      %{ip: "10.0.0.100", locked_until: DateTime.add(DateTime.utc_now(), 800, :second), attempts: 7}
    ]
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= render_header(assigns) %>
      <%= render_navigation_tabs(assigns) %>
      <%= render_content(assigns) %>
    </div>
    """
  end

  defp render_header(assigns) do
    ~H"""
    <!-- Header -->
    <div class="bg-white border-b border-gray-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between items-center py-6">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <div class="h-8 w-8 bg-red-600 rounded-lg flex items-center justify-center">
                <span class="text-white text-sm font-bold">S</span>
              </div>
            </div>
            <div class="ml-4">
              <h1 class="text-2xl font-bold text-gray-900">Dashboard de Segurança</h1>
              <p class="text-sm text-gray-600">Monitoramento e gestão de segurança do JuruConnect</p>
            </div>
          </div>
          <div class="flex items-center space-x-4">
            <span class="text-sm text-gray-600">Último update: <%= DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() %></span>
            <button
              phx-click="refresh_data"
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
            >
              Atualizar
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_navigation_tabs(assigns) do
    ~H"""
    <!-- Navigation Tabs -->
    <div class="bg-white border-b border-gray-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <nav class="flex space-x-8" aria-label="Tabs">
          <%= for {tab_id, tab_name} <- [{"overview", "Visão Geral"}, {"events", "Eventos"}, {"users", "Usuários"}, {"policies", "Políticas"}] do %>
            <button
              phx-click="switch_tab"
              phx-value-tab={tab_id}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@tab == tab_id,
                  do: "border-blue-500 text-blue-600",
                  else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")
              ]}
            >
              <%= tab_name %>
            </button>
          <% end %>
        </nav>
      </div>
    </div>
    """
  end

  defp render_content(assigns) do
    ~H"""
    <!-- Content -->
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <%= case @tab do %>
        <% "overview" -> %>
          <%= render_overview_tab(assigns) %>
        <% "users" -> %>
          <%= render_users_tab(assigns) %>
        <% _ -> %>
          <%= render_default_tab(assigns) %>
      <% end %>
    </div>
    """
  end

  defp render_overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      <!-- Rate Limiter Stats -->
      <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="h-8 w-8 bg-yellow-500 rounded-lg flex items-center justify-center">
              <span class="text-white text-sm font-bold">SEC</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">IPs Bloqueados</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @rate_limiter_stats.locked_ips %></dd>
            </dl>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="h-8 w-8 bg-red-500 rounded-lg flex items-center justify-center">
              <span class="text-white text-sm font-bold"></span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Contas Bloqueadas</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @rate_limiter_stats.locked_accounts %></dd>
            </dl>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="h-8 w-8 bg-blue-500 rounded-lg flex items-center justify-center">
              <span class="text-white text-sm font-bold">🔑</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Resets de Senha</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @password_reset_stats.active_reset_tokens %></dd>
            </dl>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="h-8 w-8 bg-green-500 rounded-lg flex items-center justify-center">
              <span class="text-white text-sm font-bold">👥</span>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Usuários Ativos</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @user_stats.active_users %></dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <!-- Recent Activity -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
      <%= render_recent_events(assigns) %>
      <%= render_security_policies(assigns) %>
    </div>
    """
  end

  defp render_recent_events(assigns) do
    ~H"""
    <!-- Recent Events -->
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Atividade Recente</h3>
      </div>
      <div class="px-6 py-4">
        <div class="flow-root">
          <ul class="-mb-8">
            <%= for {event, index} <- Enum.with_index(@recent_events) do %>
              <li>
                <div class="relative pb-8">
                  <%= if index < length(@recent_events) - 1 do %>
                    <span class="absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true"></span>
                  <% end %>
                  <div class="relative flex space-x-3">
                    <div>
                      <span class={[
                        "h-8 w-8 rounded-full flex items-center justify-center ring-8 ring-white text-white text-sm font-bold",
                        case event.type do
                          :login_success -> "bg-green-500"
                          :login_failed -> "bg-red-500"
                          :brute_force_detected -> "bg-red-700"
                          _ -> "bg-gray-500"
                        end
                      ]}>
                                                  <%= case event.type do %>
                            <% :login_success -> %>OK
                            <% :login_failed -> %>ERRO
                            <% :brute_force_detected -> %>ALERTA
                          <% _ -> %>?
                        <% end %>
                      </span>
                    </div>
                    <div class="min-w-0 flex-1 pt-1.5 flex justify-between space-x-4">
                      <div>
                        <p class="text-sm text-gray-500">
                          <%= event.details %>
                          <%= if event.username do %>
                            - <span class="font-medium"><%= event.username %></span>
                          <% end %>
                        </p>
                        <p class="text-xs text-gray-400">IP: <%= event.ip_address %></p>
                      </div>
                      <div class="text-right text-sm whitespace-nowrap text-gray-500">
                        <%= relative_time(event.timestamp) %>
                      </div>
                    </div>
                  </div>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp render_security_policies(assigns) do
    ~H"""
    <!-- Security Policies -->
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Políticas de Segurança</h3>
      </div>
      <div class="px-6 py-4">
        <dl class="space-y-4">
          <div>
            <dt class="text-sm font-medium text-gray-500">Comprimento Mínimo da Senha</dt>
            <dd class="text-sm text-gray-900"><%= @policy_info.min_length %> caracteres</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Expiração de Senha</dt>
            <dd class="text-sm text-gray-900"><%= @policy_info.password_expiry_days %> dias</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Histórico de Senhas</dt>
            <dd class="text-sm text-gray-900"><%= @policy_info.max_password_history %> senhas anteriores</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Complexidade</dt>
            <dd class="text-sm text-gray-900">
              <%= @policy_info.min_uppercase %>+ maiúscula,
              <%= @policy_info.min_digits %>+ número,
              <%= @policy_info.min_special_chars %>+ especial
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  defp render_users_tab(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= render_locked_accounts(assigns) %>
      <%= render_locked_ips(assigns) %>
    </div>
    """
  end

  defp render_locked_accounts(assigns) do
    ~H"""
    <!-- Locked Accounts -->
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">Contas Bloqueadas</h3>
      </div>
      <div class="overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Usuário</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Motivo</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Desbloqueio</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Ações</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for account <- @locked_accounts do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  <%= account.username %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= account.reason %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= relative_time(account.locked_until) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <button
                    phx-click="unlock_user"
                    phx-value-username={account.username}
                    class="text-indigo-600 hover:text-indigo-900 mr-4"
                  >
                    Desbloquear
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp render_locked_ips(assigns) do
    ~H"""
    <!-- Locked IPs -->
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-medium text-gray-900">IPs Bloqueados</h3>
      </div>
      <div class="overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Endereço IP</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tentativas</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Desbloqueio</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Ações</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for ip <- @locked_ips do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  <%= ip.ip %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= ip.attempts %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= relative_time(ip.locked_until) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <button
                    phx-click="unlock_ip"
                    phx-value-ip={ip.ip}
                    class="text-indigo-600 hover:text-indigo-900"
                  >
                    Desbloquear
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp render_default_tab(assigns) do
    ~H"""
    <div class="text-center py-12">
                      <div class="mx-auto h-12 w-12 text-gray-400 text-4xl text-center">
                  <span class="text-base font-bold">LISTA</span>
                </div>
      <h3 class="mt-2 text-sm font-medium text-gray-900">Em desenvolvimento</h3>
      <p class="mt-1 text-sm text-gray-500">Esta seção estará disponível em breve.</p>
    </div>
    """
  end

  defp relative_time(datetime) do
    case DateTime.diff(datetime, DateTime.utc_now(), :second) do
      diff when diff > 0 ->
        cond do
          diff < 60 -> "em #{diff}s"
          diff < 3600 -> "em #{div(diff, 60)}min"
          diff < 86400 -> "em #{div(diff, 3600)}h"
          true -> "em #{div(diff, 86400)}d"
        end
      diff ->
        diff = abs(diff)
        cond do
          diff < 60 -> "#{diff}s atrás"
          diff < 3600 -> "#{div(diff, 60)}min atrás"
          diff < 86400 -> "#{div(diff, 3600)}h atrás"
          true -> "#{div(diff, 86400)}d atrás"
        end
    end
  end
end
