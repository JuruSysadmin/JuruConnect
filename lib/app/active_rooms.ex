defmodule App.ActiveRooms do
  @moduledoc """
  Módulo responsável por gerenciar salas ativas (pedidos com usuários online).
  """

  use GenServer
  require Logger

  @topic "active_rooms"

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Registra um usuário em uma sala (pedido).
  """
  def join_room(order_id, user_id, user_name) when is_binary(order_id) and is_binary(user_id) and is_binary(user_name) do
    GenServer.call(__MODULE__, {:join_room, order_id, user_id, user_name})
  end

  @doc """
  Remove um usuário de uma sala.
  """
  def leave_room(order_id, user_id) when is_binary(order_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:leave_room, order_id, user_id})
  end

  @doc """
  Lista todas as salas ativas com seus usuários.
  """
  def list_active_rooms do
    GenServer.call(__MODULE__, :list_active_rooms)
  end

  @doc """
  Obtém informações de uma sala específica.
  """
  def get_room_info(order_id) when is_binary(order_id) do
    GenServer.call(__MODULE__, {:get_room_info, order_id})
  end

  @doc """
  Obtém estatísticas das salas ativas.
  """
  def get_room_stats do
    GenServer.call(__MODULE__, :get_room_stats)
  end

  # Server callbacks

  @impl true
  def init(_state) do
    # Don't subscribe to our own topic to avoid loops
    {:ok, %{}}
  end

  @impl true
  def handle_call({:join_room, order_id, user_id, user_name}, _from, state) do
    room_key = build_room_key(order_id)
    current_room = get_or_create_room(state, room_key, order_id)
    updated_room = add_user_to_room(current_room, user_id, user_name)
    new_state = Map.put(state, room_key, updated_room)

    broadcast_room_update(room_key, updated_room)
    log_user_joined(user_name, order_id, updated_room.user_count)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:leave_room, order_id, user_id}, _from, state) do
    room_key = build_room_key(order_id)

    case Map.get(state, room_key) do
      nil ->
        {:reply, :ok, state}

      room_state ->
        handle_user_leaving(state, room_key, room_state, user_id, order_id)
    end
  end

  @impl true
  def handle_call(:list_active_rooms, _from, state) do
    rooms = get_sorted_active_rooms(state)
    {:reply, rooms, state}
  end

  @impl true
  def handle_call({:get_room_info, order_id}, _from, state) do
    room_key = build_room_key(order_id)
    room_info = Map.get(state, room_key)
    {:reply, room_info, state}
  end

  @impl true
  def handle_call(:get_room_stats, _from, state) do
    stats = calculate_room_statistics(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(_msg, state) do
    # Handle any other messages (currently none)
    {:noreply, state}
  end

  # Private functions

  defp build_room_key(order_id), do: "order:#{order_id}"

  defp get_or_create_room(state, room_key, order_id) do
    Map.get(state, room_key, create_empty_room(order_id))
  end

  defp create_empty_room(order_id) do
    %{
      order_id: order_id,
      users: %{},
      last_activity: DateTime.utc_now(),
      user_count: 0
    }
  end

  defp add_user_to_room(room, user_id, user_name) do
    user_data = %{
      id: user_id,
      name: user_name,
      joined_at: DateTime.utc_now()
    }

    updated_users = Map.put(room.users, user_id, user_data)

    %{
      room |
      users: updated_users,
      user_count: map_size(updated_users),
      last_activity: DateTime.utc_now()
    }
  end

  defp handle_user_leaving(state, room_key, room_state, user_id, order_id) do
    updated_users = Map.delete(room_state.users, user_id)

    case map_size(updated_users) do
      0 ->
        remove_empty_room(state, room_key, order_id)

      _remaining_count ->
        update_room_with_remaining_users(state, room_key, room_state, updated_users, order_id)
    end
  end

  defp remove_empty_room(state, room_key, order_id) do
    new_state = Map.delete(state, room_key)
    broadcast_room_removed(room_key)
    log_room_removed(order_id)
    {:reply, :ok, new_state}
  end

  defp update_room_with_remaining_users(state, room_key, room_state, updated_users, order_id) do
    updated_room = %{
      room_state |
      users: updated_users,
      user_count: map_size(updated_users),
      last_activity: DateTime.utc_now()
    }

    new_state = Map.put(state, room_key, updated_room)
    broadcast_room_update(room_key, updated_room)
    log_user_left(order_id, updated_room.user_count)

    {:reply, :ok, new_state}
  end

  defp get_sorted_active_rooms(state) do
    state
    |> Map.values()
    |> Enum.sort_by(& &1.last_activity, {:desc, DateTime})
    |> Enum.take(20) # Limit to 20 most recent rooms
  end

  defp calculate_room_statistics(state) do
    total_rooms = map_size(state)
    total_users = calculate_total_users(state)

    %{
      total_rooms: total_rooms,
      total_users: total_users,
      average_users_per_room: calculate_average_users_per_room(total_rooms, total_users)
    }
  end

  defp calculate_total_users(state) do
    state
    |> Map.values()
    |> Enum.map(& &1.user_count)
    |> Enum.sum()
  end

  defp calculate_average_users_per_room(0, _total_users), do: 0
  defp calculate_average_users_per_room(total_rooms, total_users) do
    Float.round(total_users / total_rooms, 1)
  end

  defp log_user_joined(user_name, order_id, user_count) do
    Logger.info("User #{user_name} joined room #{order_id}. Total users: #{user_count}")
  end

  defp log_user_left(order_id, remaining_count) do
    Logger.info("User left room #{order_id}. Remaining users: #{remaining_count}")
  end

  defp log_room_removed(order_id) do
    Logger.info("Room #{order_id} removed - no users left")
  end

  defp broadcast_room_update(room_key, room_data) do
    Phoenix.PubSub.broadcast(App.PubSub, @topic, {:room_updated, room_key, room_data})
  end

  defp broadcast_room_removed(room_key) do
    Phoenix.PubSub.broadcast(App.PubSub, @topic, {:room_removed, room_key})
  end
end
