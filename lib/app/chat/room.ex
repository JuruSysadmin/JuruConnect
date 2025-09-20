defmodule App.Chat.Room do
  @moduledoc """
  GenServer for managing individual chat rooms and real-time communication.

  Handles message persistence, user presence tracking, typing indicators,
  and automatic room cleanup based on inactivity. Provides real-time
  message broadcasting via PubSub for LiveView integration.
  """

  use GenServer
  require Logger
  alias App.Chat
  alias App.ChatConfig
  alias App.DateTimeHelper

  @doc """
  Starts a new chat room GenServer for the specified order.

  Initializes the room with existing messages and sets up automatic
  inactivity monitoring for resource cleanup.
  """
  def start_link(order_id) do
    GenServer.start_link(__MODULE__, order_id, name: via_tuple(order_id))
  end

  @doc """
  Creates a via tuple for GenServer registration in the chat registry.

  Enables dynamic process registration for order-specific chat rooms,
  allowing multiple processes to be associated with the same order ID.
  """
  def via_tuple(order_id) do
    {:via, Registry, {App.ChatRegistry, order_id}}
  end

  @impl true
  def init(order_id) do
    initial_messages = load_initial_messages(order_id)
    initial_state = build_initial_state(order_id, initial_messages)
    schedule_inactivity_check()

    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:new_message, message_params}, state) do
    sender_name = resolve_sender_name(message_params.user_id)
    complete_params = build_message_params(message_params, sender_name)

    case Chat.create_message(complete_params) do
      {:ok, message} ->
        handle_successful_message(message, state)
      {:error, changeset} ->
        handle_failed_message(message_params, sender_name, changeset, state)
    end
  end

  @impl true
  def handle_cast({:start_typing, user_id}, state) do
    updated_typing_users = MapSet.put(state.typing_users, user_id)
    broadcast_typing_users(state.order_id, updated_typing_users)
    updated_state = update_activity_state(state, typing_users: updated_typing_users)

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:stop_typing, user_id}, state) do
    updated_typing_users = MapSet.delete(state.typing_users, user_id)
    broadcast_typing_users(state.order_id, updated_typing_users)
    updated_state = update_activity_state(state, typing_users: updated_typing_users)

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:join, user_data}, state) do
    Logger.info("User #{user_data.name} joined Room GenServer for order #{state.order_id}")
    updated_state = update_activity_state(state)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:check_inactivity, state) do
    if room_is_inactive?(state) do
      shutdown_inactive_room(state)
    else
      schedule_next_inactivity_check()
      {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Chat room for order #{state.order_id} is shutting down. Reason: #{inspect(reason)}")
    :ok
  end

  # Loads initial messages when the room starts
  defp load_initial_messages(order_id) do
    {:ok, messages, _has_more} = Chat.list_messages_for_order(order_id, ChatConfig.default_message_limit())
    messages
  end

  # Builds the initial state for the room
  defp build_initial_state(order_id, messages) do
    %{
      order_id: order_id,
      messages: messages,
      typing_users: MapSet.new(),
      last_activity: DateTimeHelper.now()
    }
  end

  # Schedules the first inactivity check
  defp schedule_inactivity_check do
    Process.send_after(self(), :check_inactivity, :timer.minutes(5))
  end

  # Resolves the sender name for a message
  defp resolve_sender_name(user_id) do
    get_username_by_id(user_id) || ChatConfig.default_username()
  end

  # Builds complete message parameters for database insertion
  defp build_message_params(message_params, sender_name) do
    %{
      text: message_params.text,
      sender_id: message_params.user_id,
      sender_name: sender_name,
      order_id: message_params.order_id,
      tipo: Map.get(message_params, :tipo, "mensagem"),
      timestamp: Map.get(message_params, :timestamp, DateTimeHelper.now())
    }
  end

  # Handles successful message creation
  defp handle_successful_message(message, state) do
    Logger.info("Message saved successfully: #{inspect(message)}")
    broadcast_message(state.order_id, message)
    updated_messages = state.messages ++ [message]
    updated_state = update_activity_state(state, messages: updated_messages)

    {:noreply, updated_state}
  end

  # Handles failed message creation with fallback
  defp handle_failed_message(message_params, sender_name, changeset, state) do
    Logger.error("Failed to save message: #{inspect(changeset)}")
    Logger.error("Validation errors: #{inspect(changeset.errors)}")

    temp_message = create_temp_message(message_params, sender_name)
    broadcast_message(state.order_id, temp_message)
    updated_state = update_activity_state(state)

    {:noreply, updated_state}
  end

  # Creates a temporary message for fallback broadcasting
  defp create_temp_message(message_params, sender_name) do
    %{
      id: "temp-#{System.system_time(:millisecond)}",
      text: message_params.text,
      sender_id: message_params.user_id,
      sender_name: sender_name,
      order_id: message_params.order_id,
      tipo: "mensagem",
      inserted_at: DateTimeHelper.now()
    }
  end

  # Updates the last activity timestamp and optionally other state fields
  defp update_activity_state(state, updates \\ []) do
    base_updates = [last_activity: DateTimeHelper.now()]
    all_updates = Keyword.merge(base_updates, updates)

    struct(state, all_updates)
  end

  # Checks if the room has been inactive for too long
  defp room_is_inactive?(state) do
    timeout_minutes = ChatConfig.room_inactivity_timeout()
    now = DateTimeHelper.now()
    inactive_minutes = DateTime.diff(now, state.last_activity, :second) / 60

    inactive_minutes > timeout_minutes
  end

  # Shuts down an inactive room
  defp shutdown_inactive_room(state) do
    inactive_minutes = DateTime.diff(DateTimeHelper.now(), state.last_activity, :second) / 60
    Logger.info("Chat room for order #{state.order_id} inactive for #{inactive_minutes} minutes, shutting down")
    {:stop, :normal, state}
  end

  # Schedules the next inactivity check
  defp schedule_next_inactivity_check do
    Process.send_after(self(), :check_inactivity, :timer.minutes(5))
  end

  # Broadcasts message to LiveView subscribers
  defp broadcast_message(order_id, message) do
    topic = "order:#{order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:new_message, message})
    Logger.info("Broadcasted new_message for order #{order_id}: #{inspect(message)}")
  end

  # Broadcasts typing users to LiveView subscribers
  defp broadcast_typing_users(order_id, typing_users) do
    topic = "order:#{order_id}"
    Phoenix.PubSub.broadcast(App.PubSub, topic, {:typing_users, %{users: MapSet.to_list(typing_users)}})
  end

  # Resolves username by user ID with fallback
  defp get_username_by_id(user_id) do
    case App.Accounts.get_user!(user_id) do
      nil -> ChatConfig.default_username()
      user -> user.username || ChatConfig.default_username()
    end
  rescue
    _ -> ChatConfig.default_username()
  end
end
