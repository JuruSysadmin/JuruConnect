defmodule AppWeb.UserSessionLive.Index do
  @moduledoc """
  Módulo LiveView para lidar com a funcionalidade de sessão do usuário (login).

  Este módulo oferece os seguintes recursos:
  - Renderiza o formulário de login com os campos de e-mail e senha.
  - Gerencia o estado do formulário usando um changeset do Ecto.
  - Manipula tentativas de login por meio do evento `"save"`, registrando os parâmetros enviados.
  - Permite alternar a visibilidade do campo de senha por meio do evento `"toggle_password``.

  Atribuições de soquete:
  - `:changeset` - O changeset do Ecto para o formulário de login.
  - `:show_password` - Booleano que indica se a senha deve ser visível.
  - `:email` - O valor atual da entrada de e-mail.
  - `:password` - O valor atual da entrada de senha.
  """

  use AppWeb, :live_view

  def mount(_params, _session, socket) do
    changeset = login_changeset()

    {:ok,
     assign(socket,
       changeset: changeset,
       show_password: false,
       username: "",
       password: "",
       show_register: false
     )}
  end

  def handle_event("update_email", %{"user" => %{"email" => email}}, socket) do
    {:noreply, assign(socket, email: email)}
  end

  def handle_event("save", %{"user" => %{"username" => username, "password" => password}}, socket)
      when is_binary(username) and is_binary(password) and byte_size(username) > 0 and byte_size(password) > 0 do

    with {:ok, user} <- App.Accounts.authenticate_user(username, password),
         {:ok, token, _claims} <- AppWeb.Auth.Guardian.encode_and_sign(user) do

      {:noreply,
       socket
       |> put_flash(:info, "Bem-vindo, #{user.username}!")
       |> push_navigate(to: "/auth/set-token?token=#{token}")}
    else
      {:error, :invalid_credentials} ->
        {:noreply, put_flash(socket, :error, "Usuário ou senha inválidos.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao gerar token de autenticação.")}
    end
  end

  def handle_event(
        "register",
        %{"user" => %{"username" => username, "password" => password}},
        socket
      ) when is_binary(username) and is_binary(password) and byte_size(username) > 0 and byte_size(password) > 0 do
    case get_default_store() do
      {:ok, store} ->
        attrs = %{
          "username" => username,
          "password" => password,
          "name" => username,
          "role" => "clerk",
          "store_id" => store.id
        }

        case App.Accounts.create_user(attrs) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> put_flash(:info, "Cadastro realizado com sucesso! Faça login.")
             |> assign(show_register: false)}

          {:error, changeset} ->
            msg = get_registration_error_message(changeset)
            {:noreply, put_flash(socket, :error, msg)}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Erro ao obter loja padrão.")}
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

  # Handler genérico para capturar todos os eventos
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  defp login_changeset do
    types = %{email: :string, password: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
  end

  defp get_default_store do
    case App.Stores.get_store_by!("Loja Padrão") do
      store when not is_nil(store) -> {:ok, store}
      _ -> {:error, :store_not_found}
    end
  end

  defp get_registration_error_message(changeset) do
    case Keyword.get(changeset.errors, :username) do
      {_, [constraint: :unique, constraint_name: _]} -> "Nome de usuário já existe."
      _ -> "Erro ao cadastrar usuário."
    end
  end
end
