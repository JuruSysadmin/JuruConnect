defmodule App.Jobs.ChatReminderJob do
  @moduledoc """
  Job Oban para processar lembretes do chat que chegaram na hora.

  Executa periodicamente para verificar lembretes pendentes que devem ser executados
  e enviar notificações aos usuários nos chats correspondentes.
  """

  use Oban.Worker, queue: :default
  require Logger

  alias App.Chat.ChatReminders

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case ChatReminders.get_pending_reminders() do
      reminders when reminders != [] ->
        process_reminders(reminders)
        :ok

      [] ->
        Logger.debug("ChatReminderJob: Nenhum lembrete pendente encontrado")
        :ok
    end
  end

  @doc """
  Agenda um job para processar lembretes de chat.
  """
  def schedule_job do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Agenda um job recorrente para verificação de lembretes do chat.
  """
  def schedule_recurring_job do
    # Executa a cada 5 minutos
    %{}
    |> __MODULE__.new(schedule_in: 5 * 60) # 5 minutos em segundos
    |> Oban.insert()
  end

  defp process_reminders(reminders) do
    count = Enum.reduce(reminders, 0, fn reminder, acc ->
      case process_single_reminder(reminder) do
        :ok -> acc + 1
        {:error, reason} ->
          Logger.warning("ChatReminderJob: Falha ao processar lembrete #{reminder.id}: #{inspect(reason)}")
          acc
      end
    end)

    if count > 0 do
      Logger.info("ChatReminderJob: Processados #{count} lembretes do chat")
    end

    count
  end

  defp process_single_reminder(reminder) do
    # Broadcast de notificação para o chat da tratativa
    broadcast_reminder_notification(reminder)

    # Marcar como realizado (auto-realizar notificações)
    case ChatReminders.mark_as_done(reminder.id) do
      {:ok, _updated_reminder} ->
        Logger.debug("ChatReminderJob: Lembrete #{reminder.id} processado com sucesso")
        :ok

      {:error, reason} ->
        Logger.error("ChatReminderJob: Erro ao marcar lembrete #{reminder.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp broadcast_reminder_notification(reminder) do
    topic = "treaty:#{reminder.treaty_id}"
    user_topic = "user_chat_reminders:#{reminder.user_id}"

    notification_message = %{
      type: "reminder_notification",
      reminder: %{
        id: reminder.id,
        title: reminder.title,
        description: reminder.description,
        priority: reminder.priority,
        user_id: reminder.user_id,
        treaty_id: reminder.treaty_id
      }
    }

    # Enviar para o chat da tratativa
    Phoenix.PubSub.broadcast(App.PubSub, topic, notification_message)

    # Enviar para a home do usuário
    Phoenix.PubSub.broadcast(App.PubSub, user_topic, notification_message)

    Logger.debug("ChatReminderJob: Notificação enviada para tratativa #{reminder.treaty_id} e usuário #{reminder.user_id}")
  end
end
