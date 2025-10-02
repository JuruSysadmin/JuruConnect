defmodule App.Chat.ChatRemindersTest do
  use App.DataCase, async: true

  alias App.Chat.ChatReminders
  alias App.Chat.ChatReminder
  alias App.Accounts.User
  alias App.Treaties.Treaty

  setup do
    # Criar usuário e tratativa para os testes
    user = %User{
      id: Ecto.UUID.generate(),
      name: "João Silva",
      username: "joao.silva"
    }

    treaty = %Treaty{
      id: Ecto.UUID.generate(),
      treaty_code: "TREATY-001",
      status: "active"
    }

    {:ok, user: user, treaty: treaty}
  end

  describe "create_reminder/1" do
    test "creates a reminder with valid attributes", %{user: user, treaty: treaty} do
      attrs = %{
        "user_id" => user.id,
        "treaty_id" => treaty.id,
        "title" => "Revisar contrato",
        "description" => "Verificar cláusulas importantes",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "high",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:ok, %ChatReminder{} = reminder} = ChatReminders.create_reminder(attrs)
      assert reminder.user_id == user.id
      assert reminder.treaty_id == treaty.id
      assert reminder.title == "Revisar contrato"
      assert reminder.description == "Verificar cláusulas importantes"
      assert reminder.priority == "high"
      assert reminder.status == "pending"
    end

    test "returns error with invalid attributes" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "title" => "",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -1, :hour) # Passado
      }

      assert {:error, %Ecto.Changeset{}} = ChatReminders.create_reminder(attrs)
    end

    test "requires title to be present" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "description" => "Sem título",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour)
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = ChatReminders.create_reminder(attrs)
      assert errors[:title] != nil
    end

    test "requires scheduled_at to be in the future" do
      attrs = %{
        "user_id" => Ecto.UUID.generate(),
        "treaty_id" => Ecto.UUID.generate(),
        "title" => "Teste",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -1, :hour) # Passado
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = ChatReminders.create_reminder(attrs)
      assert errors[:scheduled_at] != nil
    end
  end

  describe "get_user_chat_reminders/2" do
    test "returns reminders for a specific user and treaty", %{user: user, treaty: treaty} do
      other_treaty_id = Ecto.UUID.generate()

      # Criar alguns lembretes
      {:ok, _reminder1} = create_reminder(user.id, treaty.id, "Primeiro lembrete")
      {:ok, _reminder2} = create_reminder(user.id, other_treaty_id, "Segundo lembrete")

      reminders = ChatReminders.get_user_chat_reminders(user, treaty)

      assert length(reminders) == 1
      assert hd(reminders).title == "Primeiro lembrete"
    end

    test "filters out deleted reminders" do
      user_id = Ecto.UUID.generate()
      treaty_id = Ecto.UUID.generate()

      {:ok, reminder} = create_reminder(user_id, treaty_id, "Lembrete")

      # Deletar lembrete
      ChatReminders.delete_reminder(reminder.id)

      reminders = ChatReminders.get_user_chat_reminders(user_id, treaty_id)
      assert reminders == []
    end
  end

  describe "get_treaty_reminders/2" do
    test "returns reminders filtered by status", %{treaty: treaty} do
      user1_id = Ecto.UUID.generate()
      user2_id = Ecto.UUID.generate()

      # Criar lembretes pendentes
      {:ok, _pending1} = create_reminder(user1_id, treaty.id, "Pendente 1")
      {:ok, _pending2} = create_reminder(user2_id, treaty.id, "Pendente 2")

      # Criar lembrete concluído
      {:ok, reminder} = create_reminder(user1_id, treaty.id, "Concluído")
      {:ok, _done} = ChatReminders.mark_as_done(reminder.id)

      # Testar filtros
      pending_reminders = ChatReminders.get_treaty_reminders(treaty.id, :pending)
      done_reminders = ChatReminders.get_treaty_reminders(treaty.id, :done)

      assert length(pending_reminders) == 2
      assert length(done_reminders) == 1
    end
  end

  describe "get_pending_reminders/0" do
    test "returns reminders that should be executed now" do
      now = DateTime.utc_now()

      # Criar lembrete do passado (deve ser executado)
      {:ok, _past} = create_reminder("user-1", "treaty-1", "Passado",
        DateTime.add(now, -1, :hour))

      # Criar lembrete do futuro (não deve ser executado)
      {:ok, _future} = create_reminder("user-2", "treaty-2", "Futuro",
        DateTime.add(now, 1, :hour))

      pending = ChatReminders.get_pending_reminders()

      assert length(pending) == 1
      assert hd(pending).title == "Passado"
    end
  end

  describe "mark_as_done/1" do
    test "marks a pending reminder as done", %{user: user, treaty: treaty} do
      {:ok, reminder} = create_reminder(user.id, treaty.id, "Para marcar")

      assert {:ok, %ChatReminder{} = updated} = ChatReminders.mark_as_done(reminder.id)
      assert updated.status == "done"
      assert updated.completed_at != nil
    end

    test "returns error for non-existent reminder" do
      assert {:error, :not_found} = ChatReminders.mark_as_done("non-existent")
    end

    test "cannot mark already done reminder as done again" do
      {:ok, reminder} = create_reminder("user-123", "treaty-456", "Teste")
      {:ok, _done} = ChatReminders.mark_as_done(reminder.id)

      # Tentar marcar novamente
      assert {:error, :not_found} = ChatReminders.mark_as_done(reminder.id)
    end
  end

  describe "get_reminder_stats/2" do
    test "returns correct statistics for user and treaty", %{user: user, treaty: treaty} do
      # Criar vários lembretes
      {:ok, _low} = create_reminder(user.id, treaty.id, "Baixa", %{priority: "low"})
      {:ok, _high} = create_reminder(user.id, treaty.id, "Alta", %{priority: "high"})
      {:ok, reminder} = create_reminder(user.id, treaty.id, "Para concluir")
      {:ok, _done} = ChatReminders.mark_as_done(reminder.id)

      stats = ChatReminders.get_reminder_stats(user.id, treaty.id)

      assert stats.total_reminders == 3
      assert stats.pending_reminders == 2
      assert stats.completed_reminders == 1
      assert stats.high_priority_reminders == 1
    end
  end

  describe "search_reminders/3" do
    test "searches reminders by title and description" do
      {:ok, _title} = create_reminder("user-123", "treaty-456", "Revisar documento importante")
      {:ok, _desc} = create_reminder("user-123", "treaty-456", "Título genérico", %{
        description: "Descrição sobre contrato"
      })

      # Buscar por título
      title_results = ChatReminders.search_reminders("user-123", "treaty-456", "documento")
      assert length(title_results) == 1

      # Buscar por descrição
      desc_results = ChatReminders.search_reminders("user-123", "treaty-456", "contrato")
      assert length(desc_results) == 1

      # Buscar inexistente
      no_results = ChatReminders.search_reminders("user-123", "treaty-456", "inexistente")
      assert no_results == []
    end
  end

  describe "recurring reminders" do
    test "create_next_recurring creates new reminder for daily recurrence" do
      {:ok, reminder} = create_reminder("user-123", "treaty-456", "Diário", %{
        recurring_type: "daily",
        scheduled_at: DateTime.utc_now()
      })

      {:ok, next_reminder} = ChatReminders.create_next_recurring(reminder.id)

      assert next_reminder.recurring_type == "daily"
      assert next_reminder.status == "pending"
      assert DateTime.diff(next_reminder.scheduled_at, reminder.scheduled_at, :day) == 1
    end

    test "returns error for non-recurring reminder" do
      {:ok, reminder} = create_reminder("user-123", "treaty-456", "Não recorrente", %{
        recurring_type: "none"
      })

      assert {:error, :not_found} = ChatReminders.create_next_recurring(reminder.id)
    end
  end

  # Helper functions
  defp create_reminder(user_id, treaty_id, title, additional_attrs \\ %{}) do
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

    # Merge additional attributes directly
    merged_attrs = Map.merge(base_attrs, additional_attrs)

    ChatReminders.create_reminder(merged_attrs)
  end
end
