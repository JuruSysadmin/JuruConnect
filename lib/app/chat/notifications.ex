defmodule App.Chat.Notifications do
  @moduledoc """
  Sistema de notificações para chat, incluindo notificações de som e configurações de usuário.

  Funcionalidades principais:
  - Notificações de som quando mensagens são lidas
  - Notificações de bulk read (leitura em lote)
  - Configurações personalizadas por usuário
  - Controle de debounce para evitar spam de notificações
  - Estatísticas de uso de notificações
  - Suporte a diferentes tipos de som baseado no contexto

  ## Configurações Suportadas
  - `sound_enabled`: Habilita/desabilita sons de notificação
  - `desktop_enabled`: Habilita/desabilita notificações desktop
  - `email_enabled`: Habilita/desabilita notificações por email
  - `read_confirmations_enabled`: Habilita/desabilita confirmações de leitura

  ## Tipos de Som
  - `message_read`: Som padrão quando uma mensagem é lida
  - `bulk_read`: Som para leitura em lote de poucas mensagens (≤10)
  - `bulk_read_many`: Som especial para leitura em lote de muitas mensagens (>10)
  """

  use GenServer
  require Logger

  @notification_table :chat_notifications
  @user_settings_table :notification_settings
  @debounce_interval 5_000  # 5 segundos
  @email_batch_interval 300_000  # 5 minutos

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Envia notificação para usuário sobre nova mensagem
  """
  def notify_new_message(user_id, message, order_id) do
    GenServer.cast(__MODULE__, {:new_message, user_id, message, order_id})
  end

  @doc """
  Envia notificação de som quando uma mensagem é lida.

  Verifica as configurações do usuário antes de enviar a notificação
  e aplica debounce para evitar spam sonoro.
  """
  def notify_message_read(user_id, message_id, reader_id) do
    GenServer.cast(__MODULE__, {:message_read, user_id, message_id, reader_id})
  end

  @doc """
  Envia notificação de som para leitura em lote de mensagens.

  Usa sons diferentes baseado na quantidade de mensagens lidas:
  - 1-10 mensagens: som `bulk_read`
  - 10+ mensagens: som `bulk_read_many`
  """
  def notify_bulk_read(user_id, order_id, count, reader_id) do
    GenServer.cast(__MODULE__, {:bulk_read, user_id, order_id, count, reader_id})
  end

  @doc """
  Atualiza configurações de notificação do usuário.

  Retorna `{:ok, merged_settings}` em caso de sucesso ou
  `{:error, changeset}` em caso de configurações inválidas.
  """
  def update_user_settings(user_id, settings) do
    GenServer.call(__MODULE__, {:update_settings, user_id, settings})
  end

  @doc """
  Obtém configurações de notificação do usuário
  """
  def get_user_settings(user_id) do
    GenServer.call(__MODULE__, {:get_settings, user_id})
  end

  @doc """
  Marca notificações como lidas
  """
  def mark_notifications_read(user_id, order_id) do
    GenServer.cast(__MODULE__, {:mark_read, user_id, order_id})
  end

  @doc """
  Obtém estatísticas detalhadas de notificações.

  Retorna métricas como:
  - Total de notificações de leitura enviadas
  - Total de notificações de bulk read
  - Quantidade de sons reproduzidos
  - Contador de debounce (notificações suprimidas)
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Reseta todas as estatísticas de notificações para zero.

  Útil para testes ou limpeza periódica de métricas.
  """
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  @impl true
  def init(_state) do
    :ets.new(@notification_table, [:named_table, :public, :bag])
    :ets.new(@user_settings_table, [:named_table, :public, :set])

    # Configurações padrão para novos usuários
    default_settings = %{
      sound_enabled: true,
      desktop_enabled: true,
      email_enabled: true,
      read_confirmations_enabled: true
    }

    # Scheduler para processamento em lote de emails
    :timer.send_interval(@email_batch_interval, self(), :process_email_batch)

    {:ok, %{
      pending_notifications: %{},
      email_queue: [],
      debounce_timers: %{},
      default_settings: default_settings,
      stats: %{
        total_read_notifications: 0,
        total_bulk_notifications: 0,
        sounds_played: 0,
        debounced_count: 0,
        desktop_sent: 0,
        email_sent: 0,
        push_sent: 0
      }
    }}
  end

  @impl true
  def handle_cast({:new_message, user_id, message, order_id}, state) do
    settings = get_or_create_user_settings(user_id)

    # Verificar se usuário está online
    user_online = is_user_online?(user_id, order_id)

    if should_notify?(settings, user_online) do
      state = process_notification(user_id, message, order_id, settings, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:update_settings, user_id, settings}, _from, state) do
    case validate_user_settings(settings) do
      {:ok, valid_settings} ->
        # Mesclar com configurações existentes ou usar padrão
        existing = get_user_settings_from_ets(user_id, state.default_settings)
        merged_settings = Map.merge(existing, valid_settings)
        :ets.insert(@user_settings_table, {user_id, merged_settings})
        {:reply, {:ok, merged_settings}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_cast({:message_read, user_id, message_id, reader_id}, state) do
    user_settings = get_user_settings_from_ets(user_id, state.default_settings)

    if user_settings.sound_enabled and user_settings.read_confirmations_enabled do
      # Verificar debounce
      debounce_key = "#{user_id}_read"

      case Map.get(state.debounce_timers, debounce_key) do
        nil ->
          # Enviar notificação imediatamente
          send_sound_notification(user_id, %{
            message_id: message_id,
            reader_id: reader_id,
            sound_type: "message_read"
          })

          # Configurar timer de debounce
          timer_ref = Process.send_after(self(), {:debounce_expired, debounce_key}, @debounce_interval)
          new_timers = Map.put(state.debounce_timers, debounce_key, timer_ref)
          new_stats = Map.update!(state.stats, :total_read_notifications, &(&1 + 1))
          new_stats = Map.update!(new_stats, :sounds_played, &(&1 + 1))

          {:noreply, %{state | debounce_timers: new_timers, stats: new_stats}}

        _timer_ref ->
          # Debounce ativo - não enviar notificação
          new_stats = Map.update!(state.stats, :debounced_count, &(&1 + 1))
          {:noreply, %{state | stats: new_stats}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:bulk_read, user_id, order_id, count, reader_id}, state) do
    user_settings = get_user_settings_from_ets(user_id, state.default_settings)

    if user_settings.sound_enabled and user_settings.read_confirmations_enabled do
      sound_type = if count > 10, do: "bulk_read_many", else: "bulk_read"

      send_sound_notification(user_id, %{
        sound_type: sound_type,
        count: count,
        reader_id: reader_id,
        order_id: order_id
      })

      new_stats = Map.update!(state.stats, :total_bulk_notifications, &(&1 + 1))
      new_stats = Map.update!(new_stats, :sounds_played, &(&1 + 1))

      {:noreply, %{state | stats: new_stats}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:mark_read, user_id, order_id}, state) do
    # Remove notificações pendentes
    new_pending = Map.delete(state.pending_notifications, {user_id, order_id})
    {:noreply, %{state | pending_notifications: new_pending}}
  end

  @impl true
  def handle_call({:get_settings, user_id}, _from, state) do
    settings = get_user_settings_from_ets(user_id, state.default_settings)
    {:reply, {:ok, settings}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, {:ok, state.stats}, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    reset_stats = %{
      total_read_notifications: 0,
      total_bulk_notifications: 0,
      sounds_played: 0,
      debounced_count: 0,
      desktop_sent: 0,
      email_sent: 0,
      push_sent: 0
    }

    new_state = %{state | stats: reset_stats}
    {:reply, {:ok, :reset}, new_state}
  end

  @impl true
  def handle_info({:send_debounced_notification, user_id, order_id}, state) do
    case Map.get(state.pending_notifications, {user_id, order_id}) do
      nil ->
        {:noreply, state}

      notification_data ->
        # Enviar notificação debounced
        send_desktop_notification(user_id, notification_data)

        new_pending = Map.delete(state.pending_notifications, {user_id, order_id})
        new_stats = Map.update(state.stats, :desktop_sent, 0, &(&1 + 1))

        {:noreply, %{state |
          pending_notifications: new_pending,
          stats: new_stats
        }}
    end
  end

  @impl true
  def handle_info(:process_email_batch, state) do
    if length(state.email_queue) > 0 do
      # Processar emails em batch
      process_email_queue(state.email_queue)

      new_stats = Map.update(state.stats, :email_sent, 0, &(&1 + length(state.email_queue)))
      {:noreply, %{state | email_queue: [], stats: new_stats}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:debounce_expired, debounce_key}, state) do
    # Remover timer de debounce expirado
    new_timers = Map.delete(state.debounce_timers, debounce_key)
    {:noreply, %{state | debounce_timers: new_timers}}
  end

  defp process_notification(user_id, message, order_id, settings, state) do
    notification_data = %{
      user_id: user_id,
      message_text: truncate_message(message.text),
      sender_name: message.sender_name,
      order_id: order_id,
      timestamp: System.system_time(:second)
    }

    state = maybe_send_desktop_notification(user_id, order_id, notification_data, settings, state)
    state = maybe_queue_email_notification(user_id, notification_data, settings, state)
    state = maybe_send_push_notification(user_id, notification_data, settings, state)

    state
  end

  defp maybe_send_desktop_notification(user_id, order_id, notification_data, settings, state) do
    if settings.desktop_enabled do
      # Implementar debounce para notificações desktop
      key = {user_id, order_id}

      case Map.get(state.pending_notifications, key) do
        nil ->
          # Primeira notificação - agendar debounce
          Process.send_after(self(), {:send_debounced_notification, user_id, order_id}, @debounce_interval)

          new_pending = Map.put(state.pending_notifications, key, notification_data)
          %{state | pending_notifications: new_pending}

        _existing ->
          # Já existe notificação pendente - apenas atualizar dados
          new_pending = Map.put(state.pending_notifications, key, notification_data)
          new_stats = Map.update(state.stats, :debounced, 0, &(&1 + 1))

          %{state |
            pending_notifications: new_pending,
            stats: new_stats
          }
      end
    else
      state
    end
  end

  defp maybe_queue_email_notification(user_id, notification_data, settings, state) do
    if settings.email_enabled and not is_user_online?(user_id, notification_data.order_id) do
      email_data = %{
        user_id: user_id,
        subject: "Nova mensagem no pedido ##{notification_data.order_id}",
        message: notification_data.message_text,
        sender: notification_data.sender_name,
        order_id: notification_data.order_id
      }

      new_queue = [email_data | state.email_queue]
      %{state | email_queue: new_queue}
    else
      state
    end
  end

  defp maybe_send_push_notification(user_id, notification_data, settings, state) do
    if settings.push_enabled do
      # Enviar push notification imediatamente
      send_push_notification(user_id, notification_data)

      new_stats = Map.update(state.stats, :push_sent, 0, &(&1 + 1))
      %{state | stats: new_stats}
    else
      state
    end
  end

  defp send_desktop_notification(user_id, notification_data) do
    # Broadcast para LiveView do usuário
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "user:#{user_id}",
      {:desktop_notification, %{
        title: "Nova mensagem de #{notification_data.sender_name}",
        body: notification_data.message_text,
        icon: "/images/chat-icon.png",
        tag: "chat-#{notification_data.order_id}",
        url: "/chat/#{notification_data.order_id}"
      }}
    )
  end

  defp send_push_notification(user_id, notification_data) do
    # Implementar integração com serviço de push (Firebase, APNS, etc.)
    Logger.info("Sending push notification", %{
      user_id: user_id,
      order_id: notification_data.order_id,
      message: notification_data.message_text
    })

    # TODO: Integrar com serviço de push notifications
    # PushService.send_notification(user_id, notification_data)
  end

  defp process_email_queue(email_queue) do
    # Agrupar emails por usuário para evitar spam
    grouped_emails = Enum.group_by(email_queue, & &1.user_id)

    Enum.each(grouped_emails, fn {user_id, emails} ->
      try do
        user = App.Accounts.get_user!(user_id)
        send_digest_email(user, emails)
      rescue
        Ecto.NoResultsError ->
          Logger.warning("User not found for email notification: #{user_id}")
      end
    end)
  end

  defp send_digest_email(user, emails) do
    # Implementar envio de email digest
    Logger.info("Sending email digest", %{
      user_id: user.id,
      email_count: length(emails)
    })

    # TODO: Integrar with email service
    # EmailService.send_chat_digest(user, emails)
  end

  defp get_or_create_user_settings(user_id) do
    case :ets.lookup(@user_settings_table, user_id) do
      [] ->
        # Configurações padrão
        default_settings = %{
          desktop_enabled: true,
          email_enabled: true,
          push_enabled: true,
          sound_enabled: true,
          vibration_enabled: true
        }

        :ets.insert(@user_settings_table, {user_id, default_settings})
        default_settings

      [{^user_id, settings}] ->
        settings
    end
  end

  defp should_notify?(settings, user_online) do
    # Não notificar se usuário está online e vendo o chat
    not user_online or settings.desktop_enabled or settings.push_enabled
  end

  defp is_user_online?(user_id, order_id) do
    # Verificar se usuário está online no chat específico
    case App.Chat.MessageStatus.get_user_presence(user_id, order_id) do
      {:ok, timestamp} ->
        # Considerar online se ativo nos últimos 30 segundos
        current_time = System.system_time(:second)
        current_time - timestamp < 30

      {:error, _} ->
        false
    end
  end

  defp truncate_message(text) when is_binary(text) do
    if String.length(text) > 100 do
      String.slice(text, 0, 97) <> "..."
    else
      text
    end
  end

  defp truncate_message(_), do: "Nova mensagem"

  # Função auxiliar para obter configurações do usuário do ETS
  defp get_user_settings_from_ets(user_id, default_settings) do
    case :ets.lookup(@user_settings_table, user_id) do
      [] -> default_settings
      [{^user_id, settings}] -> Map.merge(default_settings, settings)
    end
  end

  # Função auxiliar para enviar notificação de som
  defp send_sound_notification(user_id, notification_data) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "sound_notifications:#{user_id}",
      {:play_read_sound, notification_data}
    )
  end

  # Função auxiliar para validar configurações de usuário
  defp validate_user_settings(settings) do
    changeset =
      %{}
      |> cast_settings(settings)
      |> validate_settings()

    case changeset.valid? do
      true -> {:ok, changeset.changes}
      false -> {:error, changeset}
    end
  end

  defp cast_settings(data, settings) do
    types = %{
      sound_enabled: :boolean,
      desktop_enabled: :boolean,
      email_enabled: :boolean,
      read_confirmations_enabled: :boolean
    }

    {data, types}
    |> Ecto.Changeset.cast(settings, Map.keys(types))
  end

  defp validate_settings(changeset) do
    changeset
    |> Ecto.Changeset.validate_inclusion(:sound_enabled, [true, false])
    |> Ecto.Changeset.validate_inclusion(:desktop_enabled, [true, false])
    |> Ecto.Changeset.validate_inclusion(:email_enabled, [true, false])
    |> Ecto.Changeset.validate_inclusion(:read_confirmations_enabled, [true, false])
  end
end
