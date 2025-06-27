defmodule App.ChatSupervisor do
  use DynamicSupervisor

  alias App.Chat.Room

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_chat(order_id) do
    # Verifica se já está rodando usando Registry
    case Registry.lookup(App.ChatRegistry, order_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = %{
          id: Room,
          start: {Room, :start_link, [order_id]},
          restart: :transient
        }

        DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
