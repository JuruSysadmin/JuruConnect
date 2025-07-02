defmodule App.Chat.RateLimiter do
  @moduledoc """
  Rate limiter específico para mensagens de chat.

  Previne spam e abuso do sistema de chat através de:
  - Limite de mensagens por minuto por usuário
  - Limite de mensagens idênticas
  - Detecção de comportamento suspeito
  - Escalação automática de punições
  """

  use GenServer
  require Logger

  @table_name :chat_rate_limiter
  @cleanup_interval :timer.minutes(5)

  # Configurações por minuto
  @max_messages_per_minute 15
  @max_duplicate_messages 3
  @max_long_messages_per_minute 5
  @long_message_threshold 200

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Verifica se o usuário pode enviar uma mensagem.
  Retorna {:ok, :allowed} ou {:error, reason, seconds_to_wait}
  """
  def check_message_rate(user_id, message_text) do
    GenServer.call(__MODULE__, {:check_rate, user_id, message_text})
  end

  @doc """
  Registra uma mensagem enviada com sucesso
  """
  def record_message(user_id, message_text) do
    GenServer.cast(__MODULE__, {:record_message, user_id, message_text})
  end

  @doc """
  Obtém estatísticas do rate limiter
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Remove limitações de um usuário (admin function)
  """
  def reset_user_limits(user_id) do
    GenServer.cast(__MODULE__, {:reset_limits, user_id})
  end

  @impl true
  def init(_state) do
    :ets.new(@table_name, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, %{violations: %{}}}
  end

  @impl true
  def handle_call({:check_rate, user_id, message_text}, _from, state) do
    now = System.system_time(:second)
    minute_ago = now - 60

    # Buscar mensagens do último minuto
    case :ets.lookup(@table_name, user_id) do
      [] ->
        {:reply, {:ok, :allowed}, state}

      [{^user_id, messages}] ->
        # Filtrar mensagens do último minuto
        recent_messages = Enum.filter(messages, fn {_text, timestamp} ->
          timestamp > minute_ago
        end)

        result = check_limits(user_id, message_text, recent_messages, now, state)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total_users = :ets.info(@table_name, :size)
    active_violations = map_size(state.violations)

    stats = %{
      total_tracked_users: total_users,
      active_violations: active_violations,
      violation_details: state.violations
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_message, user_id, message_text}, state) do
    now = System.system_time(:second)

    case :ets.lookup(@table_name, user_id) do
      [] ->
        :ets.insert(@table_name, {user_id, [{message_text, now}]})

      [{^user_id, messages}] ->
        updated_messages = [{message_text, now} | messages]
        :ets.insert(@table_name, {user_id, updated_messages})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset_limits, user_id}, state) do
    :ets.delete(@table_name, user_id)
    new_violations = Map.delete(state.violations, user_id)

    Logger.info("Rate limits reset for user #{user_id}")
    {:noreply, %{state | violations: new_violations}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_messages()
    schedule_cleanup()
    {:noreply, state}
  end

  defp check_limits(user_id, message_text, recent_messages, _now, state) do
    message_count = length(recent_messages)
    duplicate_count = count_duplicates(message_text, recent_messages)
    long_message_count = count_long_messages(recent_messages, @long_message_threshold)

    cond do
      message_count >= @max_messages_per_minute ->
        record_violation(user_id, :too_many_messages, state)
        {:error, :rate_limited, calculate_wait_time(60)}

      duplicate_count >= @max_duplicate_messages ->
        record_violation(user_id, :duplicate_spam, state)
        {:error, :duplicate_spam, calculate_wait_time(120)}

      String.length(message_text) > @long_message_threshold and
      long_message_count >= @max_long_messages_per_minute ->
        record_violation(user_id, :long_message_spam, state)
        {:error, :long_message_spam, calculate_wait_time(90)}

      true ->
        {:ok, :allowed}
    end
  end

  defp count_duplicates(message_text, messages) do
    normalized_message = String.downcase(String.trim(message_text))

    Enum.count(messages, fn {text, _timestamp} ->
      String.downcase(String.trim(text)) == normalized_message
    end)
  end

  defp count_long_messages(messages, threshold) do
    Enum.count(messages, fn {text, _timestamp} ->
      String.length(text) > threshold
    end)
  end

  defp record_violation(user_id, type, state) do
    current_count = Map.get(state.violations, user_id, %{}) |> Map.get(type, 0)

    violation_data = %{
      type: type,
      timestamp: System.system_time(:second),
      count: current_count + 1
    }

    new_violations = Map.update(state.violations, user_id, %{type => violation_data}, fn user_violations ->
      Map.put(user_violations, type, violation_data)
    end)

    Logger.warning("Chat rate limit violation", %{
      user_id: user_id,
      violation_type: type,
      count: violation_data.count
    })

    %{state | violations: new_violations}
  end

  defp calculate_wait_time(base_seconds) do
    # Adiciona um pouco de jitter para evitar thundering herd
    base_seconds + :rand.uniform(10)
  end

  defp cleanup_old_messages do
    now = System.system_time(:second)
    minute_ago = now - 60

    :ets.foldl(fn {user_id, messages}, _acc ->
      filtered_messages = Enum.filter(messages, fn {_text, timestamp} ->
        timestamp > minute_ago
      end)

      if Enum.empty?(filtered_messages) do
        :ets.delete(@table_name, user_id)
      else
        :ets.insert(@table_name, {user_id, filtered_messages})
      end

      :ok
    end, :ok, @table_name)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
