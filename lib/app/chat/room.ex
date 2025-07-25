defmodule App.Chat.Room do
  @moduledoc """
  GenServer que gerencia salas de chat para pedidos específicos.

  Cada sala de chat mantém o estado das mensagens, usuários conectados
  e usuários que estão digitando. Monitora inatividade para encerrar
  salas não utilizadas automaticamente.
  """

  use GenServer
  alias App.Chat
  alias App.ChatConfig


  # Client API
  def start_link(order_id) do
    GenServer.start_link(__MODULE__, order_id, name: via_tuple(order_id))
  end

  def via_tuple(order_id) do
    {:via, Registry, {App.ChatRegistry, order_id}}
  end

  # GenServer Callbacks
  @impl true
  def init(order_id) do
    # Load messages when the room starts, using the configured limit
    {:ok, messages, _has_more} =
      Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit())

    # The state includes the order_id, the list of messages, and users who are currently typing.
    {:ok,
     %{
       order_id: order_id,
       messages: messages,
       typing_users: MapSet.new(),
       last_activity: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_cast(
        {:new_message, %{text: text, user_id: user_id, order_id: order_id} = message_params},
        state
      ) do
    # Obter o nome do usuário
    sender_name = get_username_by_id(user_id) || ChatConfig.default_username()

    # Preparar os parâmetros completos para a mensagem
    complete_params = %{
      text: text,
      sender_id: user_id,
      sender_name: sender_name,
      order_id: order_id,
      tipo: Map.get(message_params, :tipo, "mensagem"),
      timestamp: Map.get(message_params, :timestamp, DateTime.utc_now())
    }

    # Criar mensagem com parâmetros completos

    # Persist the message to the database with the generated ID
    case Chat.create_message(complete_params) do
      {:ok, message} ->
        # Broadcast the new message to all LiveView subscribers via PubSub
        broadcast_message(state.order_id, message)

        # Add the new message to the local state (optional, but good for consistency)
        new_messages = state.messages ++ [message]
        new_state = %{state | messages: new_messages, last_activity: DateTime.utc_now()}
        {:noreply, new_state}

      {:error, _changeset} ->
        # Mesmo se falhar ao salvar no banco, vamos transmitir a mensagem para os clientes
        # com um ID temporário para garantir que ela apareça no frontend
        temp_message = %{
          id: "temp-#{System.system_time(:millisecond)}",
          text: text,
          sender_id: user_id,
          sender_name: sender_name,
          order_id: order_id,
          tipo: "mensagem",
          inserted_at: DateTime.utc_now()
        }

        broadcast_message(state.order_id, temp_message)

        {:noreply, %{state | last_activity: DateTime.utc_now()}}
    end
  end

  @impl true
  def handle_cast({:start_typing, user_id}, state) do
    typing_users = MapSet.put(state.typing_users, user_id)
    broadcast_typing_users(state.order_id, typing_users)
    {:noreply, %{state | typing_users: typing_users, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:stop_typing, user_id}, state) do
    typing_users = MapSet.delete(state.typing_users, user_id)
    broadcast_typing_users(state.order_id, typing_users)
    {:noreply, %{state | typing_users: typing_users, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:join, _user_data}, state) do
    # Quando um usuário entra, podemos querer enviar o estado atual de digitação
    # para ele, ou apenas registrar a entrada.
    {:noreply, %{state | last_activity: DateTime.utc_now()}}
  end

  # Adicionar função para verificar inatividade
  @impl true
  def handle_info(:check_inactivity, state) do
    timeout_minutes = ChatConfig.room_inactivity_timeout()
    now = DateTime.utc_now()
    diff = DateTime.diff(now, state.last_activity, :second) / 60

    if diff > timeout_minutes do
      {:stop, :normal, state}
    else
      # Agendar próxima verificação
      Process.send_after(self(), :check_inactivity, :timer.minutes(5))
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  # Broadcast message to LiveView subscribers
  defp broadcast_message(order_id, message) do
    topic = "order:#{order_id}"

    # Broadcast via PubSub for LiveView subscribers
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
  end

  defp broadcast_typing_users(order_id, typing_users) do
    topic = "order:#{order_id}"
    # We convert the Set to a List for JSON serialization
    Phoenix.PubSub.broadcast(
      App.PubSub,
      topic,
      {:typing_users, %{users: MapSet.to_list(typing_users)}}
    )
  end

  # Helper para obter o nome do usuário pelo ID (você precisará implementar isso)
  defp get_username_by_id(user_id) do
    case App.Accounts.get_user_by_username(user_id) do
      nil -> ChatConfig.default_username()
      user -> user.username || ChatConfig.default_username()
    end
  rescue
    # Fallback em caso de erro
    _ -> ChatConfig.default_username()
  end
end
