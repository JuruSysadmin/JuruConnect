defmodule AppWeb.PresenceContext do
  @moduledoc """
  Contexto para lógica de negócio relacionada a presença de usuários.
  
  Este módulo encapsula toda a lógica de negócio para:
  - Rastreamento de presença de usuários
  - Gerenciamento de usuários online
  - Notificações de entrada/saída
  - Integração com ActiveRooms
  """

  alias AppWeb.Presence
  alias App.DateTimeHelper

  @doc """
  Configura o rastreamento de presença para um usuário.
  
  ## Parâmetros
  - `topic`: Tópico do chat
  - `socket`: Socket do LiveView
  - `user_name`: Nome do usuário
  - `authenticated_user`: Usuário autenticado (pode ser nil)
  - `treaty_id`: ID da tratativa
  
  ## Retorno
  - `:ok` - Presença configurada
  - `{:error, reason}` - Erro na configuração
  """
  def setup_presence_tracking(topic, socket, user_name, authenticated_user, treaty_id) do
    user_data = build_user_data(socket, user_name, authenticated_user)
    
    case Presence.track(self(), topic, socket.id, user_data) do
      {:ok, _} ->
        join_active_room_if_authenticated(authenticated_user, treaty_id, user_name)
        :ok
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  Obtém lista de usuários online a partir das presenças.
  
  ## Parâmetros
  - `presences`: Map de presenças
  
  ## Retorno
  - `users_online` - Lista de nomes de usuários online
  """
  def extract_users_from_presences(presences) when is_map(presences) do
    presences
    |> Map.values()
    |> Enum.flat_map(&extract_names_from_metas/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
  def extract_users_from_presences(_), do: []

  @doc """
  Obtém presenças de um tópico de forma segura.
  
  ## Parâmetros
  - `topic`: Tópico do chat
  
  ## Retorno
  - `presences` - Map de presenças ou map vazio em caso de erro
  """
  def safely_get_presences(topic) do
    try do
      Presence.list(topic)
    rescue
      _ -> %{}
    end
  end

  @doc """
  Remove usuário do ActiveRooms quando desconecta.
  
  ## Parâmetros
  - `treaty_id`: ID da tratativa
  - `user_id`: ID do usuário
  """
  def leave_active_room(treaty_id, user_id) do
    case Process.whereis(App.ActiveRooms) do
      nil -> :ok
      _pid ->
        try do
          App.ActiveRooms.leave_room(treaty_id, user_id)
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc """
  Obtém inicial do nome do usuário para avatar.
  
  ## Parâmetros
  - `user`: Nome do usuário
  
  ## Retorno
  - `initial` - Letra inicial em maiúscula
  """
  def get_user_initial(user) when is_binary(user) and byte_size(user) > 0 do
    user |> String.first() |> String.upcase()
  end
  def get_user_initial(_), do: "U"

  @doc """
  Verifica se há mudança no status de conexão.
  
  ## Parâmetros
  - `is_connected`: Status atual de conexão
  - `previous_connected`: Status anterior de conexão
  
  ## Retorno
  - `transition_state` - Estado da transição ("connecting", "disconnecting", "stable")
  """
  def get_connection_transition_state(is_connected, previous_connected) do
    if is_connected != previous_connected do
      if is_connected, do: "connecting", else: "disconnecting"
    else
      "stable"
    end
  end

  @doc """
  Obtém classes CSS para indicador de conexão.
  
  ## Parâmetros
  - `is_connected`: Status de conexão
  - `transition_state`: Estado da transição
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_connection_indicator_classes(is_connected, transition_state) do
    base_classes = "w-1.5 h-1.5 rounded-full mr-1 shadow-sm transition-colors duration-500"
    
    case {is_connected, transition_state} do
      {true, "connecting"} -> base_classes <> " bg-yellow-500 animate-pulse"
      {true, "stable"} -> base_classes <> " bg-emerald-500 animate-pulse"
      {false, "disconnecting"} -> base_classes <> " bg-yellow-500 animate-pulse"
      {false, "stable"} -> base_classes <> " bg-red-500"
      _ -> base_classes <> " bg-gray-500"
    end
  end

  @doc """
  Obtém classes CSS para texto de conexão.
  
  ## Parâmetros
  - `is_connected`: Status de conexão
  - `transition_state`: Estado da transição
  
  ## Retorno
  - `classes` - String com classes CSS
  """
  def get_connection_text_classes(is_connected, transition_state) do
    base_classes = "font-medium transition-colors duration-500"
    
    case {is_connected, transition_state} do
      {true, "connecting"} -> base_classes <> " text-yellow-600"
      {true, "stable"} -> base_classes <> " text-emerald-600"
      {false, "disconnecting"} -> base_classes <> " text-yellow-600"
      {false, "stable"} -> base_classes <> " text-red-600"
      _ -> base_classes <> " text-gray-600"
    end
  end

  # Funções privadas

  defp build_user_data(socket, user_name, authenticated_user) do
    %{
      user_id: get_user_id_for_presence(authenticated_user),
      name: user_name,
      joined_at: DateTimeHelper.now() |> DateTime.to_iso8601(),
      user_agent: get_connect_info(socket, :user_agent) || "Desconhecido"
    }
  end

  defp get_user_id_for_presence(nil), do: "anonimo"
  defp get_user_id_for_presence(%{id: id}), do: id

  defp join_active_room_if_authenticated(nil, _treaty_id, _user_name), do: :ok
  defp join_active_room_if_authenticated(authenticated_user, treaty_id, user_name) do
    case Process.whereis(App.ActiveRooms) do
      nil -> :ok
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

  defp get_connect_info(socket, key) do
    Phoenix.LiveView.get_connect_info(socket, key)
  end
end
