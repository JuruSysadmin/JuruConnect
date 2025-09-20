defmodule AppWeb.UserSessionLive.Index do
  @moduledoc """
  LiveView for user authentication and registration.

  Provides login and registration functionality with form validation,
  password visibility toggle, and JWT token generation for authenticated users.
  """

  use AppWeb, :live_view
  require Logger

  @doc """
  Mounts the user session LiveView.

  Initializes the login form with empty changeset and default state.
  """
  def mount(_params, _session, socket) do
    login_changeset = create_login_changeset()

    {:ok,
     assign(socket,
       changeset: login_changeset,
       show_password: false,
       username: "",
       password: "",
       show_register: false
     )}
  end

  def handle_event("update_email", %{"user" => %{"email" => email}}, socket) do
    {:noreply, assign(socket, email: email)}
  end

  @doc """
  Handles user login authentication.

  Validates credentials, generates JWT token on success,
  and redirects to token setting page.
  """
  def handle_event("save", %{"user" => %{"username" => username, "password" => password}}, socket) do
    Logger.info("Login attempt for username: #{username}")

    case App.Accounts.authenticate_user(username, password) do
      {:ok, authenticated_user} ->
        handle_successful_authentication(socket, authenticated_user)

      {:error, :invalid_credentials} ->
        handle_failed_authentication(socket, username)
    end
  end

  def handle_event("register", %{"user" => %{"username" => username, "password" => password}}, socket) do
    default_store = App.Stores.get_store_by!("Loja Padrão")

    user_attributes = %{
      "username" => username,
      "password" => password,
      "name" => username,
      "role" => "clerk",
      "store_id" => default_store.id
    }

    case App.Accounts.create_user(user_attributes) do
      {:ok, _new_user} ->
        handle_successful_registration(socket)

      {:error, changeset} ->
        handle_failed_registration(socket, changeset)
    end
  end

  def handle_event("show_register", _params, socket) do
    {:noreply, assign(socket, show_register: true)}
  end

  def handle_event("show_login", _params, socket) do
    {:noreply, assign(socket, show_register: false)}
  end

  def handle_event("toggle_password", _params, socket) do
    {:noreply, update(socket, :show_password, &(!&1))}
  end

  # Handles successful user authentication
  defp handle_successful_authentication(socket, authenticated_user) do
    Logger.info("User authenticated successfully: #{authenticated_user.username}")

    case AppWeb.Auth.Guardian.encode_and_sign(authenticated_user) do
      {:ok, jwt_token, _claims} ->
        Logger.info("Token generated successfully for user: #{authenticated_user.username}")
        {:noreply,
         socket
         |> put_flash(:info, "Bem-vindo, #{authenticated_user.username}!")
         |> push_navigate(to: "/auth/set-token?token=#{jwt_token}")}

      {:error, reason} ->
        Logger.error("Failed to generate token: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Erro ao gerar token de autenticação.")}
    end
  end

  # Handles failed authentication
  defp handle_failed_authentication(socket, username) do
    Logger.warning("Invalid credentials for username: #{username}")
    {:noreply, put_flash(socket, :error, "Usuário ou senha inválidos.")}
  end

  # Handles successful user registration
  defp handle_successful_registration(socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Cadastro realizado com sucesso! Faça login.")
     |> assign(show_register: false)}
  end

  # Handles failed user registration
  defp handle_failed_registration(socket, changeset) do
    error_message = extract_registration_error(changeset)

    {:noreply, put_flash(socket, :error, error_message)}
  end

  # Extracts specific error message from registration changeset
  defp extract_registration_error(changeset) do
    case Keyword.get(changeset.errors, :username) do
      {_, [constraint: :unique, constraint_name: _]} -> "Nome de usuário já existe."
      _ -> "Erro ao cadastrar usuário."
    end
  end

  # Creates an empty changeset for the login form
  defp create_login_changeset do
    types = %{email: :string, password: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
  end
end
