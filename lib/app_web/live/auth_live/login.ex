defmodule AppWeb.AuthLive.Login do
  @moduledoc """
  Interface de login moderna com funcionalidades avançadas.

  Inclui:
  - Login seguro com rate limiting
  - Recuperação de senha
  - Validação em tempo real
  - Interface responsiva e acessível
  """

  use AppWeb, :live_view

  alias App.Auth.{Manager, PasswordReset, PasswordPolicy}
  alias App.Accounts

  def mount(_params, _session, socket) do
    # Store IP address during mount as connect_info is only available here
    ip_address = case get_connect_info(socket, :peer_data) do
      %{address: address} -> :inet_parse.ntoa(address) |> to_string()
      _ -> "127.0.0.1"  # Usar localhost como padrão quando IP não puder ser determinado
    end

    {:ok,
     assign(socket,
       # Form states
       mode: :login,  # :login, :forgot_password, :reset_password
       form: to_form(%{"username" => "", "password" => ""}),
       forgot_form: to_form(%{"email_or_username" => ""}),

       # UI states
       show_password: false,
       loading: false,
       password_strength: nil,

       # Flash states
       success_message: nil,
       error_message: nil,

       # Rate limiting
       rate_limited: false,
       retry_after: 0,
       captcha_required: false,

       # Password reset
       reset_token: nil,
       reset_mode: false,

       # Client info (stored during mount)
       client_ip: ip_address
     )}
  end

  def handle_params(%{"token" => token}, _uri, socket) do
    case PasswordReset.validate_reset_token(token) do
      {:ok, _reset_data} ->
        {:noreply,
         socket
         |> assign(mode: :reset_password, reset_token: token)
         |> put_flash(:info, "Token válido. Defina sua nova senha.")}

      {:error, :token_expired} ->
        {:noreply,
         socket
         |> assign(mode: :forgot_password)
         |> put_flash(:error, "Token expirado. Solicite um novo link de recuperação.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(mode: :login)
         |> put_flash(:error, "Token inválido. Faça login normalmente.")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: String.to_atom(mode), error_message: nil)}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, show_password: !socket.assigns.show_password)}
  end

  def handle_event("validate_login", %{"username" => username, "password" => password}, socket) do
    form = to_form(%{"username" => username, "password" => password})

    # Validação em tempo real da força da senha (apenas visual)
    password_strength = if String.length(password) > 0 do
      PasswordPolicy.password_strength(password)
    else
      nil
    end

    {:noreply, assign(socket, form: form, password_strength: password_strength)}
  end

  def handle_event("validate_forgot", %{"email_or_username" => email_or_username}, socket) do
    form = to_form(%{"email_or_username" => email_or_username})
    {:noreply, assign(socket, forgot_form: form)}
  end

  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      auth_params = %{
        username: String.trim(username),
        password: password,
        ip_address: socket.assigns.client_ip
      }

      socket = assign(socket, loading: true, error_message: nil)

      case Manager.authenticate(auth_params) do
                {:ok, %{user: user, access_token: token, captcha_required: _captcha_required}} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:info, "Bem-vindo de volta, #{user.name || user.username}!")
           |> push_navigate(to: "/sessions/callback?token=#{token}&user_id=#{user.id}")}

        {:error, {:rate_limited, retry_after}} ->
          {:noreply,
           socket
           |> assign(loading: false, rate_limited: true, retry_after: retry_after)
           |> put_flash(:error, "Muitas tentativas. Aguarde #{retry_after} segundos.")}

        {:error, :invalid_credentials} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "Usuário ou senha inválidos.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "Erro interno. Tente novamente.")}
      end
    end
  end

  def handle_event("forgot_password", %{"email_or_username" => email_or_username}, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      socket = assign(socket, loading: true, error_message: nil)

      case PasswordReset.request_password_reset(email_or_username, socket.assigns.client_ip) do
        {:ok, :reset_email_sent} ->
          {:noreply,
           socket
           |> assign(loading: false, mode: :login)
           |> put_flash(:info, "Se o usuário existir, um e-mail de recuperação foi enviado.")}

        {:error, :daily_limit_exceeded} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "Limite diário de recuperação atingido. Tente novamente amanhã.")}

        {:error, :rate_limited} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:error, "Muitas tentativas. Aguarde alguns minutos.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(loading: false)
           |> put_flash(:info, "Se o usuário existir, um e-mail de recuperação foi enviado.")}
      end
    end
  end

    def handle_event("reset_password", %{"password" => password, "password_confirmation" => password_confirmation}, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      perform_password_reset(socket, password, password_confirmation)
    end
  end

  def handle_event("validate_reset_password", %{"password" => password}, socket) do
    password_strength = if String.length(password) > 0 do
      PasswordPolicy.password_strength(password)
    else
      nil
    end

    {:noreply, assign(socket, password_strength: password_strength)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 via-white to-purple-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo e Header -->
        <div class="text-center">
          <div class="mx-auto h-16 w-16 bg-gradient-to-br from-blue-600 to-purple-600 rounded-2xl flex items-center justify-center shadow-lg">
            <span class="text-white text-2xl font-bold">J</span>
          </div>
          <h2 class="mt-6 text-3xl font-bold text-gray-900">
            <%= case @mode do %>
              <% :login -> %>JuruConnect
              <% :forgot_password -> %>Recuperar Senha
              <% :reset_password -> %>Nova Senha
            <% end %>
          </h2>
          <p class="mt-2 text-sm text-gray-600">
            <%= case @mode do %>
              <% :login -> %>Faça login em sua conta
              <% :forgot_password -> %>Digite seu usuário ou e-mail
              <% :reset_password -> %>Defina sua nova senha
            <% end %>
          </p>
        </div>

        <!-- Formulários -->
        <div class="bg-white rounded-2xl shadow-xl border border-gray-100 p-8">
          <%= if @mode == :login do %>
            <.form for={@form} phx-submit="login" phx-change="validate_login" class="space-y-6">
              <div>
                <label for="username" class="block text-sm font-medium text-gray-700 mb-2">
                  Usuário
                </label>
                <input
                  id="username"
                  name="username"
                  type="text"
                  value={@form.params["username"]}
                  required
                  class="appearance-none relative block w-full px-4 py-3 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 focus:z-10 transition-all duration-200"
                  placeholder="Digite seu usuário"
                  autocomplete="username"
                />
              </div>

              <div>
                <label for="password" class="block text-sm font-medium text-gray-700 mb-2">
                  Senha
                </label>
                <div class="relative">
                  <input
                    id="password"
                    name="password"
                    type={if @show_password, do: "text", else: "password"}
                    value={@form.params["password"]}
                    required
                    class="appearance-none relative block w-full px-4 py-3 pr-12 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 focus:z-10 transition-all duration-200"
                    placeholder="Digite sua senha"
                    autocomplete="current-password"
                  />
                  <button
                    type="button"
                    phx-click="toggle_password"
                    class="absolute inset-y-0 right-0 pr-3 flex items-center"
                    tabindex="-1"
                  >
                    <span class="text-gray-400 hover:text-gray-600 text-sm">
                      <%= if @show_password, do: "🙈", else: "👁️" %>
                    </span>
                  </button>
                </div>
              </div>

              <div class="flex items-center justify-between">
                <div class="text-sm">
                  <button
                    type="button"
                    phx-click="switch_mode"
                    phx-value-mode="forgot_password"
                    class="font-medium text-blue-600 hover:text-blue-500 transition-colors duration-200"
                  >
                    Esqueceu sua senha?
                  </button>
                </div>
              </div>

              <div>
                <button
                  type="submit"
                  disabled={@loading || @rate_limited}
                  class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 shadow-lg hover:shadow-xl"
                >
                  <%= if @loading do %>
                    <span class="animate-spin mr-3">⏳</span>
                    Entrando...
                  <% else %>
                    Entrar
                  <% end %>
                </button>
              </div>
            </.form>

          <% end %>

          <%= if @mode == :forgot_password do %>
            <.form for={@forgot_form} phx-submit="forgot_password" phx-change="validate_forgot" class="space-y-6">
              <div>
                <label for="email_or_username" class="block text-sm font-medium text-gray-700 mb-2">
                  Usuário ou E-mail
                </label>
                <input
                  id="email_or_username"
                  name="email_or_username"
                  type="text"
                  value={@forgot_form.params["email_or_username"]}
                  required
                  class="appearance-none relative block w-full px-4 py-3 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 focus:z-10 transition-all duration-200"
                  placeholder="Digite seu usuário ou e-mail"
                />
              </div>

              <div class="space-y-4">
                <button
                  type="submit"
                  disabled={@loading}
                  class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 shadow-lg hover:shadow-xl"
                >
                  <%= if @loading do %>
                    <span class="animate-spin mr-3">⏳</span>
                    Enviando...
                  <% else %>
                    Enviar Link de Recuperação
                  <% end %>
                </button>

                <button
                  type="button"
                  phx-click="switch_mode"
                  phx-value-mode="login"
                  class="w-full text-center py-2 px-4 text-sm font-medium text-gray-600 hover:text-gray-800 transition-colors duration-200"
                >
                  ← Voltar ao Login
                </button>
              </div>
            </.form>

          <% end %>

          <%= if @mode == :reset_password do %>
            <.form for={%{}} phx-submit="reset_password" phx-change="validate_reset_password" class="space-y-6">
              <div>
                <label for="password" class="block text-sm font-medium text-gray-700 mb-2">
                  Nova Senha
                </label>
                <div class="relative">
                  <input
                    id="password"
                    name="password"
                    type={if @show_password, do: "text", else: "password"}
                    required
                    class="appearance-none relative block w-full px-4 py-3 pr-12 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 focus:z-10 transition-all duration-200"
                    placeholder="Digite sua nova senha"
                  />
                  <button
                    type="button"
                    phx-click="toggle_password"
                    class="absolute inset-y-0 right-0 pr-3 flex items-center"
                    tabindex="-1"
                  >
                    <span class="text-gray-400 hover:text-gray-600 text-sm">
                      <%= if @show_password, do: "🙈", else: "👁️" %>
                    </span>
                  </button>
                </div>
              </div>

              <div>
                <label for="password_confirmation" class="block text-sm font-medium text-gray-700 mb-2">
                  Confirmar Nova Senha
                </label>
                <input
                  id="password_confirmation"
                  name="password_confirmation"
                  type={if @show_password, do: "text", else: "password"}
                  required
                  class="appearance-none relative block w-full px-4 py-3 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 focus:z-10 transition-all duration-200"
                  placeholder="Confirme sua nova senha"
                />
              </div>

              <%= if @password_strength do %>
                <div class="bg-gray-50 rounded-lg p-4">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-gray-700">Força da Senha</span>
                    <span class={"text-sm font-medium text-#{@password_strength.color}-600"}>
                      <%= case @password_strength.level do %>
                        <% :very_weak -> %>"Muito Fraca"
                        <% :weak -> %>"Fraca"
                        <% :moderate -> %>"Moderada"
                        <% :strong -> %>"Forte"
                        <% :very_strong -> %>"Muito Forte"
                      <% end %>
                    </span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div class={"bg-#{@password_strength.color}-500 h-2 rounded-full transition-all duration-300"} style={"width: #{@password_strength.score}%"}></div>
                  </div>
                  <%= if length(@password_strength.feedback) > 0 do %>
                    <ul class="mt-2 text-sm text-gray-600">
                      <%= for feedback <- @password_strength.feedback do %>
                        <li class="flex items-center">
                          <span class="text-yellow-500 mr-1">⚠️</span>
                          <%= feedback %>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              <% end %>

              <button
                type="submit"
                disabled={@loading}
                class="group relative w-full flex justify-center py-3 px-4 border border-transparent text-sm font-medium rounded-xl text-white bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 shadow-lg hover:shadow-xl"
              >
                <%= if @loading do %>
                  <span class="animate-spin mr-3">⏳</span>
                  Alterando Senha...
                <% else %>
                  Alterar Senha
                <% end %>
              </button>
            </.form>

          <% end %>
        </div>

        <!-- Policy Info -->
        <%= if @mode in [:reset_password] do %>
          <div class="bg-blue-50 border border-blue-200 rounded-xl p-4">
            <h4 class="text-sm font-medium text-blue-800 mb-2">Requisitos da Senha</h4>
            <ul class="text-xs text-blue-700 space-y-1">
              <li>• Mínimo de 8 caracteres</li>
              <li>• Pelo menos 1 letra maiúscula</li>
              <li>• Pelo menos 1 letra minúscula</li>
              <li>• Pelo menos 1 número</li>
              <li>• Pelo menos 1 caractere especial</li>
            </ul>
          </div>
        <% end %>

        <!-- Footer -->
        <div class="text-center">
          <p class="text-xs text-gray-500">
            © <%= Date.utc_today().year %> Jurunense Home Center - JuruConnect
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp perform_password_reset(socket, password, password_confirmation) do
    cond do
      password != password_confirmation ->
        {:noreply, put_flash(socket, :error, "As senhas não conferem.")}

      String.length(password) == 0 ->
        {:noreply, put_flash(socket, :error, "A senha não pode estar vazia.")}

      true ->
        case PasswordPolicy.validate_password(password) do
          {:ok, _strength} ->
            execute_password_reset(socket, password)

          {:error, errors} ->
            error_message = "Senha inválida: " <> Enum.join(errors, ", ")
            {:noreply, put_flash(socket, :error, error_message)}
        end
    end
  end

  defp execute_password_reset(socket, password) do
    socket = assign(socket, loading: true, error_message: nil)

    case PasswordReset.reset_password(socket.assigns.reset_token, password, socket.assigns.client_ip) do
      {:ok, :password_reset_successful} ->
        {:noreply,
         socket
         |> assign(loading: false, mode: :login, reset_token: nil)
         |> put_flash(:info, "Senha alterada com sucesso! Faça login com sua nova senha.")}

      {:error, :token_expired} ->
        {:noreply,
         socket
         |> assign(loading: false, mode: :forgot_password, reset_token: nil)
         |> put_flash(:error, "Token expirado. Solicite um novo link de recuperação.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(loading: false)
         |> put_flash(:error, "Erro ao alterar senha. Tente novamente.")}
    end
  end
end
