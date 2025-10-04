defmodule AppWeb.ChatLive.AuthHelper do
  @moduledoc """
  Helper responsável apenas pela autenticação e autorização do chat.

  Este módulo centraliza toda a lógica relacionada a:
  - Validação de tokens Guardian
  - Resolução de identidade de usuários
  - Verificação de permissões para ações específicas
  - Extração de dados de usuário de sessões
  """

  use Phoenix.LiveView
  alias AppWeb.ChatConfig

  @doc """
  Hook de autenticação que valida tokens de sessão do usuário.

  Garante acesso seguro verificando tokens Guardian dos dados de sessão
  antes de permitir participação no chat. Usuários anônimos são permitidos
  mas com funcionalidade limitada.
  """
  def on_mount(:default, _params, session, socket) do
    case session["user_token"] do
      nil ->
        {:cont, socket}

      token ->
        case AppWeb.Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            {:cont, assign(socket, :current_user, user)}

          {:error, _reason} ->
            {:cont, socket}
        end
    end
  end

  @doc """
  Resolve a identidade do usuário a partir do socket ou sessão.

  Retorna uma tupla {nome_do_usuário, objeto_do_usuário} onde:
  - nome_do_usuário: string com o nome para exibição
  - objeto_do_usuário: struct do usuário ou nil para usuários anônimos
  """
  def resolve_user_identity(%{assigns: %{current_user: nil}}, session) do
    extract_user_from_session_token(session)
  end

  def resolve_user_identity(%{assigns: %{current_user: user}}, _session) do
    extract_user_from_socket_assigns(user)
  end

  def resolve_user_identity(socket, session) do
    # Fallback para sockets que não têm a estrutura esperada
    case socket.assigns[:current_user] do
      nil -> extract_user_from_session_token(session)
      user -> extract_user_from_socket_assigns(user)
    end
  end

  @doc """
  Verifica se o usuário pode encerrar uma tratativa específica.

  Retorna true se o usuário tem permissão para encerrar a tratativa,
  false caso contrário.
  """
  def can_close_treaty?(%{assigns: %{user_object: nil}}), do: false

  def can_close_treaty?(%{assigns: %{user_object: user, treaty: treaty}}) do
    App.Accounts.can_close_treaty?(user, treaty)
  end

  def can_close_treaty?(_socket), do: false

  @doc """
  Verifica se o usuário está autenticado.

  Retorna true se o usuário está logado, false caso contrário.
  """
  def authenticated?(%{assigns: %{user_object: nil}}), do: false
  def authenticated?(%{assigns: %{user_object: _user}}), do: true
  def authenticated?(_socket), do: false

  @doc """
  Obtém o ID do usuário para uso em presença.

  Retorna o ID do usuário ou "anonimo" para usuários não autenticados.
  """
  def get_user_id_for_presence(nil), do: "anonimo"
  def get_user_id_for_presence(%{id: id}), do: id

  @doc """
  Obtém informações do usuário para envio de mensagens.

  Retorna uma tupla {user_id, user_name} onde:
  - user_id: ID do usuário ou nil para usuários anônimos
  - user_name: nome do usuário para exibição
  """
  def get_user_info_for_message(%{assigns: %{user_object: nil, current_user: current_user}}) do
    {nil, current_user}
  end

  def get_user_info_for_message(%{assigns: %{user_object: %{id: id, name: name}, current_user: _}}) when not is_nil(name) do
    {id, name}
  end

  def get_user_info_for_message(%{assigns: %{user_object: %{id: id, username: username}, current_user: _}}) when not is_nil(username) do
    {id, username}
  end

  def get_user_info_for_message(%{assigns: %{user_object: %{id: id}, current_user: current_user}}) do
    {id, current_user}
  end

  @doc """
  Processa ações específicas para usuários autenticados.

  Registra acesso à tratativa e marca notificações como lidas.
  """
  def handle_authenticated_user_actions(socket, authenticated_user, treaty_id) do
    case authenticated_user do
      %{id: user_id} ->
        App.Accounts.record_order_access(user_id, treaty_id)
        App.Notifications.mark_all_notifications_as_read(user_id)
        socket
      nil ->
        socket
    end
  end

  # Funções privadas para extração de dados de usuário

  defp extract_user_from_session_token(%{"user_token" => nil}) do
    default_username = ChatConfig.get_config_value(:ui, :default_username) || "Usuario"
    {default_username, nil}
  end

  defp extract_user_from_session_token(%{"user_token" => token}) when is_binary(token) do
    default_username = ChatConfig.get_config_value(:ui, :default_username) || "Usuario"

    case AppWeb.Auth.Guardian.resource_from_token(token) do
      {:ok, %{name: name} = user, _claims} when not is_nil(name) ->
        {name, user}

      {:ok, %{username: username} = user, _claims} when not is_nil(username) ->
        {username, user}

      {:ok, user, _claims} ->
        {default_username, user}

      {:error, _reason} ->
        {default_username, nil}
    end
  end

  defp extract_user_from_session_token(_session) do
    default_username = ChatConfig.get_config_value(:ui, :default_username) || "Usuario"
    {default_username, nil}
  end

  defp extract_user_from_socket_assigns(%{name: name} = user) when not is_nil(name) do
    {name, user}
  end

  defp extract_user_from_socket_assigns(%{username: username} = user) when not is_nil(username) do
    {username, user}
  end

  defp extract_user_from_socket_assigns(user) do
    default_name = ChatConfig.get_config_value(:ui, :default_username) || "Usuario"
    {default_name, user}
  end
end
