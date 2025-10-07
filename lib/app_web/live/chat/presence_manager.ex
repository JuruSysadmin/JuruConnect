defmodule AppWeb.ChatLive.PresenceManager do
  @moduledoc """
  Módulo responsável por gerenciar a presença de usuários no chat.

  Encapsula toda a lógica relacionada ao Phoenix.Presence, incluindo:
  - Rastreamento de usuários online
  - Extração de dados de presença
  - Configuração de dados do usuário
  - Tratamento de erros de presença
  """

  alias AppWeb.Presence
  alias AppWeb.ChatLive.AuthHelper
  alias App.DateTimeHelper

  @doc """
  Configura o rastreamento de presença para um usuário em um tópico específico.

  ## Parâmetros
  - `topic`: Tópico do chat (ex: "treaty:123")
  - `socket`: Socket do LiveView
  - `user_name`: Nome do usuário
  - `authenticated_user`: Usuário autenticado (pode ser nil)
  - `treaty_id`: ID da tratativa
  - `user_agent`: User agent do navegador (opcional)

  ## Retorno
  - `:ok` se o rastreamento foi configurado com sucesso
  - `:error` se houve falha no rastreamento
  """
  def track_user_presence(topic, socket, user_name, authenticated_user, treaty_id, user_agent \\ "Desconhecido") do
    user_data = build_user_data(socket, user_name, authenticated_user, user_agent)

    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
        handle_successful_tracking(authenticated_user, treaty_id, user_name)
        :ok
      {:error, reason} ->
        require Logger
        Logger.warning("Failed to track presence for user #{user_name}: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Obtém a lista de presenças para um tópico específico.

  ## Parâmetros
  - `topic`: Tópico do chat

  ## Retorno
  - Map com as presenças ou mapa vazio em caso de erro
  """
  def get_presences(topic) do
    try do
      Presence.list(topic)
    rescue
      error ->
        require Logger
        Logger.warning("Failed to get presences for topic #{topic}: #{inspect(error)}")
        %{}
    end
  end

  @doc """
  Extrai os nomes dos usuários online a partir das presenças.

  ## Parâmetros
  - `presences`: Map com as presenças

  ## Retorno
  - Lista de nomes de usuários únicos e ordenados
  """
  def extract_online_users(presences) when is_map(presences) do
    presences
    |> Map.values()
    |> Enum.flat_map(&extract_names_from_metas/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def extract_online_users(_), do: []

  @doc """
  Verifica se um usuário específico está online em uma tratativa.

  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `user_id`: ID do usuário

  ## Retorno
  - `true` se o usuário está online
  - `false` se o usuário está offline ou não encontrado
  """
  def user_online?(treaty_id, user_id) do
    topic = "treaty:#{treaty_id}"
    presences = get_presences(topic)

    presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{user_id: user_id} -> user_id end)
    end)
    |> Enum.member?(user_id)
  end

  @doc """
  Obtém informações de presença formatadas para exibição.

  ## Parâmetros
  - `treaty_id`: ID da tratativa

  ## Retorno
  - Map com informações formatadas de presença
  """
  def get_presence_info(treaty_id) do
    topic = "treaty:#{treaty_id}"
    presences = get_presences(topic)
    online_users = extract_online_users(presences)

    %{
      presences: presences,
      online_users: online_users,
      online_count: length(online_users),
      topic: topic
    }
  end

  # Funções privadas

  defp build_user_data(_socket, user_name, authenticated_user, user_agent) do
    %{
      user_id: AuthHelper.get_user_id_for_presence(authenticated_user),
      name: user_name,
      joined_at: DateTimeHelper.now() |> DateTime.to_iso8601(),
      user_agent: user_agent
    }
  end

  defp handle_successful_tracking(nil, _treaty_id, _user_name), do: :ok

  defp handle_successful_tracking(authenticated_user, treaty_id, user_name) do
    case Process.whereis(App.ActiveRooms) do
      nil ->
        :ok
      _pid ->
        try do
          App.ActiveRooms.join_room(treaty_id, authenticated_user.id, user_name)
        rescue
          _e -> :ok
        catch
          :exit, _reason -> :ok
        end
    end
  end

  defp extract_names_from_metas(%{metas: metas}) when is_list(metas) do
    Enum.map(metas, fn %{name: name} when is_binary(name) -> name end)
  end

  defp extract_names_from_metas(_), do: []
end
