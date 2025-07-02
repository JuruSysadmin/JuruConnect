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

  @initial_form_data %{"username" => "", "password" => ""}
  @initial_forgot_form_data %{"email_or_username" => ""}

  def mount(_params, _session, socket) do
    ip_address = extract_client_ip(socket)

    {:ok,
     assign(socket,
       mode: :login,
       form: to_form(@initial_form_data),
       forgot_form: to_form(@initial_forgot_form_data),
       show_password: false,
       loading: false,
       password_strength: nil,
       success_message: nil,
       error_message: nil,
       rate_limited: false,
       retry_after: 0,
       captcha_required: false,
       reset_token: nil,
       reset_mode: false,
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
    {:noreply, assign(socket, mode: String.to_existing_atom(mode), error_message: nil)}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, show_password: not socket.assigns.show_password)}
  end

  def handle_event("validate_login", params, socket) do
    form_data = extract_login_params(params)
    form = to_form(form_data)
    password_strength = calculate_password_strength(form_data.password)

    {:noreply, assign(socket, form: form, password_strength: password_strength)}
  end

  def handle_event("validate_forgot", params, socket) do
    form_data = extract_forgot_params(params)
    form = to_form(form_data)
    {:noreply, assign(socket, forgot_form: form)}
  end

  def handle_event("login", params, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      perform_login(socket, params)
    end
  end

  def handle_event("forgot_password", params, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      perform_forgot_password(socket, params)
    end
  end

  def handle_event("reset_password", params, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      perform_password_reset(socket, params)
    end
  end

  def handle_event("validate_reset_password", %{"password" => password}, socket) do
    password_strength = calculate_password_strength(password)
    {:noreply, assign(socket, password_strength: password_strength)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 via-white to-purple-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div class="text-center">
          <div class="mx-auto h-16 w-16 bg-gradient-to-br from-blue-600 to-purple-600 rounded-2xl flex items-center justify-center shadow-lg">
            <span class="text-white text-2xl font-bold">J</span>
          </div>
          <h2 class="mt-6 text-3xl font-bold text-gray-900">
            <%= header_text(@mode) %>
          </h2>
          <p class="mt-2 text-sm text-gray-600">
            <%= subtitle_text(@mode) %>
          </p>
        </div>

        <div class="bg-white rounded-2xl shadow-xl border border-gray-100 p-8">
          <%= render_form_by_mode(assigns) %>
        </div>

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

        <div class="text-center">
          <p class="text-xs text-gray-500">
            © <%= Date.utc_today().year %> Jurunense Home Center - JuruConnect
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp extract_client_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} -> :inet_parse.ntoa(address) |> to_string()
      _ -> "127.0.0.1"
    end
  end

  defp extract_login_params(params) do
    %{
      "username" => Map.get(params, "username", ""),
      "password" => Map.get(params, "password", "")
    }
  end

  defp extract_forgot_params(params) do
    %{
      "email_or_username" => Map.get(params, "email_or_username", "")
    }
  end

  defp calculate_password_strength(password) when byte_size(password) > 0 do
    PasswordPolicy.password_strength(password)
  end

  defp calculate_password_strength(_), do: nil

  defp perform_login(socket, params) do
    login_data = extract_login_params(params)

    auth_params = build_auth_params(login_data, socket.assigns.client_ip)
    socket = assign(socket, loading: true, error_message: nil)

    case Manager.authenticate(auth_params) do
      {:ok, %{user: user, access_token: token}} ->
        handle_successful_login(socket, user, token)

      {:error, {:rate_limited, retry_after}} ->
        handle_rate_limited(socket, retry_after)

      {:error, :invalid_credentials} ->
        handle_invalid_credentials(socket)

      {:error, _reason} ->
        handle_auth_error(socket)
    end
  end

  defp build_auth_params(login_data, client_ip) do
    %{
      username: String.trim(login_data["username"]),
      password: login_data["password"],
      ip_address: client_ip
    }
  end

  defp handle_successful_login(socket, user, token) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:info, "Bem-vindo de volta, #{user.name || user.username}!")
     |> push_navigate(to: "/sessions/callback?token=#{token}&user_id=#{user.id}")}
  end

  defp handle_rate_limited(socket, retry_after) do
    {:noreply,
     socket
     |> assign(loading: false, rate_limited: true, retry_after: retry_after)
     |> put_flash(:error, "Muitas tentativas. Aguarde #{retry_after} segundos.")}
  end

  defp handle_invalid_credentials(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Usuário ou senha inválidos.")}
  end

  defp handle_auth_error(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Erro interno. Tente novamente.")}
  end

  defp perform_forgot_password(socket, params) do
    forgot_data = extract_forgot_params(params)
    socket = assign(socket, loading: true, error_message: nil)

    case PasswordReset.request_password_reset(
           forgot_data["email_or_username"],
           socket.assigns.client_ip
         ) do
      {:ok, :reset_email_sent} ->
        handle_reset_email_sent(socket)

      {:error, :daily_limit_exceeded} ->
        handle_daily_limit_exceeded(socket)

      {:error, :rate_limited} ->
        handle_reset_rate_limited(socket)

      {:error, _reason} ->
        handle_reset_error(socket)
    end
  end

  defp handle_reset_email_sent(socket) do
    {:noreply,
     socket
     |> assign(loading: false, mode: :login)
     |> put_flash(:info, "Se o usuário existir, um e-mail de recuperação foi enviado.")}
  end

  defp handle_daily_limit_exceeded(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Limite diário de recuperação atingido. Tente novamente amanhã.")}
  end

  defp handle_reset_rate_limited(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Muitas tentativas. Aguarde alguns minutos.")}
  end

  defp handle_reset_error(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:info, "Se o usuário existir, um e-mail de recuperação foi enviado.")}
  end

  defp perform_password_reset(socket, params) do
    password = Map.get(params, "password", "")
    password_confirmation = Map.get(params, "password_confirmation", "")

    cond do
      password != password_confirmation ->
        {:noreply, put_flash(socket, :error, "As senhas não conferem.")}

      String.length(password) == 0 ->
        {:noreply, put_flash(socket, :error, "A senha não pode estar vazia.")}

      true ->
        validate_and_reset_password(socket, password)
    end
  end

  defp validate_and_reset_password(socket, password) do
    case PasswordPolicy.validate_password(password) do
      {:ok, _strength} ->
        execute_password_reset(socket, password)

      {:error, errors} ->
        error_message = "Senha inválida: " <> Enum.join(errors, ", ")
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  defp execute_password_reset(socket, password) do
    socket = assign(socket, loading: true, error_message: nil)

    case PasswordReset.reset_password(
           socket.assigns.reset_token,
           password,
           socket.assigns.client_ip
         ) do
      {:ok, :password_reset_successful} ->
        handle_password_reset_success(socket)

      {:error, :token_expired} ->
        handle_password_reset_expired(socket)

      {:error, _reason} ->
        handle_password_reset_error(socket)
    end
  end

  defp handle_password_reset_success(socket) do
    {:noreply,
     socket
     |> assign(loading: false, mode: :login, reset_token: nil)
     |> put_flash(:info, "Senha alterada com sucesso! Faça login com sua nova senha.")}
  end

  defp handle_password_reset_expired(socket) do
    {:noreply,
     socket
     |> assign(loading: false, mode: :forgot_password, reset_token: nil)
     |> put_flash(:error, "Token expirado. Solicite um novo link de recuperação.")}
  end

  defp handle_password_reset_error(socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Erro ao alterar senha. Tente novamente.")}
  end

  defp header_text(:login), do: "JuruConnect"
  defp header_text(:forgot_password), do: "Recuperar Senha"
  defp header_text(:reset_password), do: "Nova Senha"

  defp subtitle_text(:login), do: "Faça login em sua conta"
  defp subtitle_text(:forgot_password), do: "Digite seu usuário ou e-mail"
  defp subtitle_text(:reset_password), do: "Defina sua nova senha"

  defp render_form_by_mode(%{mode: :login} = assigns) do
    ~H"""
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
              <%= if @show_password, do: "Ocultar", else: "Mostrar" %>
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
            <span class="animate-spin mr-3">•</span>
            Entrando...
          <% else %>
            Entrar
          <% end %>
        </button>
      </div>
    </.form>
    """
  end

  defp render_form_by_mode(%{mode: :forgot_password} = assigns) do
    ~H"""
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
            <span class="animate-spin mr-3">•</span>
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
    """
  end

  defp render_form_by_mode(%{mode: :reset_password} = assigns) do
    ~H"""
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
              <%= if @show_password, do: "Ocultar", else: "Mostrar" %>
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
              <%= password_strength_label(@password_strength.level) %>
            </span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div class={"bg-#{@password_strength.color}-500 h-2 rounded-full transition-all duration-300"} style={"width: #{@password_strength.score}%"}></div>
          </div>
          <%= if length(@password_strength.feedback) > 0 do %>
            <ul class="mt-2 text-sm text-gray-600">
              <%= for feedback <- @password_strength.feedback do %>
                <li class="flex items-center">
                  <span class="text-yellow-500 mr-1 font-bold">AVISO:</span>
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
          <span class="animate-spin mr-3">•</span>
          Alterando Senha...
        <% else %>
          Alterar Senha
        <% end %>
      </button>
    </.form>
    """
  end

  defp password_strength_label(:very_weak), do: "Muito Fraca"
  defp password_strength_label(:weak), do: "Fraca"
  defp password_strength_label(:moderate), do: "Moderada"
  defp password_strength_label(:strong), do: "Forte"
  defp password_strength_label(:very_strong), do: "Muito Forte"
end
