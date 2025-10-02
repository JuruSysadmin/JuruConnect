defmodule App.Jobs.ChatReminderJobTest do
  use App.DataCase, async: false  # Precisa ser false para PubSub

  alias App.Jobs.ChatReminderJob
  alias App.Chat.ChatReminders
  alias App.Repo
  alias App.Chat.ChatReminder
  alias App.Accounts.User
  alias App.Treaties.Treaty

  setup do
    # Iniciar PubSub para testes
    start_supervised!(App.PubSub)

    user = %User{
      id: "user-123",
      name: "João Silva",
      username: "joao.silva"
    }

    treaty = %Treaty{
      id: "treaty-456",
      treaty_code: "TREATY-001",
      status: "active"
    }

    {:ok, user: user, treaty: treaty}
  end

  describe "perform/1" do
    test "processes pending reminders and notifies users", %{user: user, treaty: treaty} do
      # Criar lembrete que deve ser executado (passado)
      past_time = DateTime.add(DateTime.utc_now(), -1, :hour)

      {:ok, reminder} = create_reminder(user.id, treaty.id, "Teste", %{
        scheduled_at: past_time
      })

      # Subscribir aos tópicos para verificar broadcasts
      Phoenix.PubSub.subscribe(App.PubSub, "treaty:#{treaty.id}")
      Phoenix.PubSub.subscribe(App.PubSub, "user_chat_reminders:#{user.id}")

      # Executar job
      assert ChatReminderJob.perform(%Oban.Job{args: %{}}) == :ok

      # Verificar que lembrete foi marcado como realizado
      updated_reminder = Repo.get(ChatReminder, reminder.id)
      assert updated_reminder.status == "done"
      assert updated_reminder.completed_at != nil

      # Verificar broadcasts via PubSub
      assert_receive %{type: "reminder_notification", reminder: received_reminder}, 1000
      assert received_reminder.id == reminder.id
      assert received_reminder.title == "Teste"
      assert received_reminder.user_id == user.id
    end

    test "does not process future reminders", %{user: user, treaty: treaty} do
      # Criar lembrete futuro (não deve ser processado)
      future_time = DateTime.add(DateTime.utc_now(), 1, :hour)

      {:ok, _future_reminder} = create_reminder(user.id, treaty.id, "Futuro", %{
        scheduled_at: future_time
      })

      # Executar job
      assert ChatReminderJob.perform(%Oban.Job{args: %{}}) == :ok

      # Verificar que lembrete NÃO foi marcado como realizado
      reminders = ChatReminders.get_user_chat_reminders(user, treaty)
      assert length(reminders) == 1
      assert hd(reminders).status == "pending"

      # Não deve haver broadcasts
      refute_receive %{type: "reminder_notification", reminder: _}, 100
    end

    test "handles multiple pending reminders correctly" do
      user1_id = "user-1"
      user2_id = "user-2"
      treaty_id = "treaty-123"
      past_time = DateTime.add(DateTime.utc_now(), -30, :minute)

      # Criar múltiplos lembretes
      {:ok, _reminder1} = create_reminder(user1_id, treaty_id, "Lembrete 1", %{
        scheduled_at: past_time
      })

      {:ok, _reminder2} = create_reminder(user2_id, treaty_id, "Lembrete 2", %{
        scheduled_at: past_time
      })

      # Executar job
      assert ChatReminderJob.perform(%Oban.Job{args: %{}}) == :ok

      # Verificar que ambos foram processados
      pending_reminders = ChatReminders.get_treaty_reminders(treaty_id, :pending)
      done_reminders = ChatReminders.get_treaty_reminders(treaty_id, :done)

      assert length(pending_reminders) == 0
      assert length(done_reminders) == 2
    end

    test "returns :ok when no reminders need processing" do
      # Não criar nenhum lembrete

      # Executar job
      assert ChatReminderJob.perform(%Oban.Job{args: %{}}) == :ok

      # Não deve haver broadcasts
      refute_receive %{type: "reminder_notification", reminder: _}, 100
    end

    test "handles errors gracefully when reminder not found" do
      # Simular situação onde lembrete foi deletado após buscar pendentes
      past_time = DateTime.add(DateTime.utc_now(), -1, :hour)

      {:ok, reminder} = create_reminder("user-123", "treaty-456", "Para deletar", %{
        scheduled_at: past_time
      })

      # Buscar lembretes pendentes primeiro
      pending = ChatReminders.get_pending_reminders()
      assert length(pending) == 1

      # Deletar lembrete antes do processamento
      ChatReminders.delete_reminder(reminder.id)

      # Executar job - deve completar sem erro
      assert ChatReminderJob.perform(%Oban.Job{args: %{}}) == :ok
    end
  end

  describe "broadcast_reminder_notification/1" do
    test "broadcasts to both treaty topic and user topic", %{user: user, treaty: treaty} do
      # Criar lembrete
      {:ok, reminder} = create_reminder(user.id, treaty.id, "Notificação teste")

      # Subscribir aos dois tópicos
      Phoenix.PubSub.subscribe(App.PubSub, "treaty:#{treaty.id}")
      Phoenix.PubSub.subscribe(App.PubSub, "user_chat_reminders:#{user.id}")

      # Criar job e chamar broadcast diretamente
      job = %ChatReminderJob{}

      # Chamar através de perform para executar o broadcast
      ChatReminderJob.perform(%Oban.Job{args: %{}})

      # Deve receber mensagem nos dois tópicos
      assert_receive %{type: "reminder_notification", reminder: reminder_data}
      assert_receive %{type: "reminder_notification", reminder: reminder_data}

      assert reminder_data.id == reminder.id
      assert reminder_data.title == "Notificação teste"
      assert reminder_data.user_id == user.id
      assert reminder_data.treaty_id == treaty.id
    end
  end

  describe "schedule_job/0" do
    test "creates a new job for immediate execution" do
      # Mock do Oban para testes
      with_mock Oban, [insert: fn(_job) -> {:ok, %Oban.Job{id: 1}} end] do
        result = ChatReminderJob.schedule_job()
        assert result == {:ok, %Oban.Job{id: 1}}

        # Verificar se insert foi chamado com os argumentos corretos
        assert_called Oban.insert(%ChatReminderJob{args: %{}})
      end
    end
  end

  describe "schedule_recurring_job/0" do
    test "creates a job scheduled for 5 minutes from now" do
      with_mock Oban, [insert: fn(_job) -> {:ok, %Oban.Job{id: 1}} end] do
        result = ChatReminderJob.schedule_recurring_job()
        assert result == {:ok, %Oban.Job{id: 1}}

        # Verificar se foi chamado com schedule_in correto
        assert_called Oban.insert(%ChatReminderJob{schedule_in: 300}) # 5 min em segundos
      end
    end
  end

  # Helper para criar lembretes de teste
  defp create_reminder(user_id, treaty_id, title, attrs \\ %{}) do
    base_attrs = %{
      "user_id" => user_id,
      "treaty_id" => treaty_id,
      "title" => title,
      "description" => "Descrição do teste",
      "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
      "priority" => "medium",
      "notification_type" => "popup",
      "recurring_type" => "none"
    }

    merged_attrs = Map.merge(base_attrs, Map.from_struct(attrs))

    # Converter keys para strings se necessário
    string_attrs = Enum.reduce(merged_attrs, %{}, fn {k, v}, acc ->
      key = case k do
        atom when is_atom(atom) -> Atom.to_string(atom)
        str when is_binary(str) -> str
      end
      Map.put(acc, key, v)
    end)

    ChatReminders.create_reminder(string_attrs)
  end
end
