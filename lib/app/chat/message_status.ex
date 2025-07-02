defmodule App.Chat.MessageStatus do
  @moduledoc """
  Gerencia o status das mensagens no chat.

  Controla:
  - Mensagens entregues
  - Mensagens lidas
  - Notificações de leitura
  - Últimas visualizações por usuário
  """

  use GenServer
  require Logger

  @status_table :message_status
  @user_presence_table :user_presence
  @cleanup_interval :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Marca uma mensagem como entregue para um usuário
  """
  def mark_delivered(message_id, user_id) do
    GenServer.cast(__MODULE__, {:mark_delivered, message_id, user_id})
  end

  @doc """
  Marca uma mensagem como lida por um usuário
  """
  def mark_read(message_id, user_id) do
    GenServer.cast(__MODULE__, {:mark_read, message_id, user_id})
  end

  @doc """
  Marca todas as mensagens como lidas até uma determinada mensagem
  """
  def mark_all_read_until(last_message_id, user_id, order_id) do
    GenServer.cast(__MODULE__, {:mark_all_read_until, last_message_id, user_id, order_id})
  end

  @doc """
  Atualiza a presença do usuário (última atividade)
  """
  def update_user_presence(user_id, order_id) do
    GenServer.cast(__MODULE__, {:update_presence, user_id, order_id})
  end

  @doc """
  Obtém o status de uma mensagem
  """
  def get_message_status(message_id) do
    GenServer.call(__MODULE__, {:get_status, message_id})
  end

  @doc """
  Obtém mensagens não lidas para um usuário em um pedido
  """
  def get_unread_count(user_id, order_id) do
    GenServer.call(__MODULE__, {:get_unread_count, user_id, order_id})
  end

  @doc """
  Obtém estatísticas de leitura de mensagens
  """
  def get_read_stats(order_id) do
    GenServer.call(__MODULE__, {:get_read_stats, order_id})
  end

  @doc """
  Obtém presença do usuário
  """
  def get_user_presence(user_id, order_id) do
    case :ets.lookup(@user_presence_table, user_id) do
      [] -> {:error, :not_found}
      [{^user_id, ^order_id, timestamp}] -> {:ok, timestamp}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def init(_state) do
    # Tabela para status de mensagens
    :ets.new(@status_table, [:named_table, :public, :bag])
    # Tabela para presença de usuários
    :ets.new(@user_presence_table, [:named_table, :public, :set])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:mark_delivered, message_id, user_id}, state) do
    timestamp = System.system_time(:second)
    :ets.insert(@status_table, {message_id, user_id, :delivered, timestamp})

    # Broadcast para LiveView
    Phoenix.PubSub.broadcast(App.PubSub, "message_status:#{message_id}",
      {:status_update, message_id, user_id, :delivered})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mark_read, message_id, user_id}, state) do
    timestamp = System.system_time(:second)
    :ets.insert(@status_table, {message_id, user_id, :read, timestamp})

    # Broadcast para LiveView
    Phoenix.PubSub.broadcast(App.PubSub, "message_status:#{message_id}",
      {:status_update, message_id, user_id, :read})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mark_all_read_until, last_message_id, user_id, order_id}, state) do
    timestamp = System.system_time(:second)

    # Buscar todas as mensagens do pedido até a última mensagem
    {:ok, messages} = App.Chat.list_messages_until(order_id, last_message_id)

    Enum.each(messages, fn message ->
      :ets.insert(@status_table, {message.id, user_id, :read, timestamp})
    end)

    # Broadcast bulk read update
    Phoenix.PubSub.broadcast(App.PubSub, "order:#{order_id}",
      {:bulk_read_update, user_id, length(messages)})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_presence, user_id, order_id}, state) do
    timestamp = System.system_time(:second)
    :ets.insert(@user_presence_table, {user_id, order_id, timestamp})

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_status, message_id}, _from, state) do
    statuses = :ets.lookup(@status_table, message_id)

    result = %{
      delivered_to: [],
      read_by: []
    }

    final_result = Enum.reduce(statuses, result, fn {_msg_id, user_id, status, timestamp}, acc ->
      case status do
        :delivered ->
          %{acc | delivered_to: [{user_id, timestamp} | acc.delivered_to]}
        :read ->
          %{acc | read_by: [{user_id, timestamp} | acc.read_by]}
      end
    end)

    {:reply, final_result, state}
  end

  @impl true
  def handle_call({:get_unread_count, user_id, order_id}, _from, state) do
    # Implementação simplificada - contar mensagens sem status de leitura
    {:ok, count} = App.Chat.count_unread_messages(user_id, order_id)
    {:reply, count, state}
  end

  @impl true
  def handle_call({:get_read_stats, order_id}, _from, state) do
    {:ok, stats} = App.Chat.get_message_read_stats(order_id)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_status()
    schedule_cleanup()
    {:noreply, state}
  end

  defp cleanup_old_status do
    # Remove status de mensagens antigas (mais de 7 dias)
    cutoff = System.system_time(:second) - (7 * 24 * 60 * 60)

    :ets.foldl(fn {message_id, user_id, status, timestamp}, _acc ->
      if timestamp < cutoff do
        :ets.delete_object(@status_table, {message_id, user_id, status, timestamp})
      end
      :ok
    end, :ok, @status_table)

    # Remove presenças antigas (mais de 1 dia)
    presence_cutoff = System.system_time(:second) - (24 * 60 * 60)

    :ets.foldl(fn {user_id, order_id, timestamp}, _acc ->
      if timestamp < presence_cutoff do
        :ets.delete_object(@user_presence_table, {user_id, order_id, timestamp})
      end
      :ok
    end, :ok, @user_presence_table)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
