defmodule App.Chat.Room do
  use GenServer
  alias App.Chat
  alias App.ChatConfig
  alias App.DateTimeHelper

  def start_link(treaty_id) do
    GenServer.start_link(__MODULE__, treaty_id, name: via_tuple(treaty_id))
  end

  def via_tuple(treaty_id) do
    {:via, Registry, {App.ChatRegistry, treaty_id}}
  end

  @impl true
  def init(treaty_id) do
    {:ok, messages, _has_more} = Chat.list_messages_for_treaty(treaty_id, ChatConfig.default_message_limit())
    {:ok, %{treaty_id: treaty_id, messages: messages, typing_users: MapSet.new(), last_activity: DateTimeHelper.now()}}
  end

  @impl true
  def handle_cast({:new_message, %{text: text, user_id: user_id, treaty_id: treaty_id} = message_params}, state)
      when is_binary(text) and is_binary(user_id) and is_binary(treaty_id) do
    sender_name = get_username_by_id(user_id) || ChatConfig.default_username()

    complete_params = %{
      text: text,
      sender_id: user_id,
      sender_name: sender_name,
      treaty_id: treaty_id,
      tipo: Map.get(message_params, :tipo, "mensagem"),
      timestamp: Map.get(message_params, :timestamp, DateTimeHelper.now())
    }

    case Chat.create_message(complete_params) do
      {:ok, message} ->
        broadcast_message(state.treaty_id, message)
        new_messages = [message | state.messages]
        new_state = %{state | messages: new_messages, last_activity: DateTimeHelper.now()}
        {:noreply, new_state}

      {:error, _changeset} ->
        temp_message = %{
          id: "temp-#{System.system_time(:millisecond)}",
          text: text,
          sender_id: user_id,
          sender_name: sender_name,
          treaty_id: treaty_id,
          tipo: "mensagem",
          inserted_at: DateTimeHelper.now()
        }

        broadcast_message(state.treaty_id, temp_message)
        {:noreply, %{state | last_activity: DateTimeHelper.now()}}
    end
  end

  @impl true
  def handle_cast({:start_typing, user_id}, state) do
    typing_users = MapSet.put(state.typing_users, user_id)
    broadcast_typing_users(state.treaty_id, typing_users)

    {:noreply, %{state | typing_users: typing_users, last_activity: DateTimeHelper.now()}}
  end

  @impl true
  def handle_cast({:stop_typing, user_id}, state) do
    typing_users = MapSet.delete(state.typing_users, user_id)
    broadcast_typing_users(state.treaty_id, typing_users)

    {:noreply, %{state | typing_users: typing_users, last_activity: DateTimeHelper.now()}}
  end

  @impl true
  def handle_cast({:join, _user_data}, state) do
    {:noreply, %{state | last_activity: DateTimeHelper.now()}}
  end

  @impl true
  def handle_info(:check_inactivity, state) do
    timeout_minutes = ChatConfig.room_inactivity_timeout()
    now = DateTimeHelper.now()
    diff = DateTime.diff(now, state.last_activity, :second) / 60

    if diff > timeout_minutes do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :check_inactivity, :timer.minutes(5))
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  defp broadcast_message(treaty_id, message) do
    topic = "treaty:#{treaty_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
  end

  defp broadcast_typing_users(treaty_id, typing_users) do
    topic = "treaty:#{treaty_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_users, %{users: MapSet.to_list(typing_users)}})
  end

  defp get_username_by_id(user_id) when is_binary(user_id) do
    try do
      user = App.Accounts.get_user!(user_id)
      user.username || ChatConfig.default_username()
    rescue
      Ecto.NoResultsError -> ChatConfig.default_username()
      _ -> ChatConfig.default_username()
    end
  end

  defp get_username_by_id(_), do: ChatConfig.default_username()
end
