defmodule App.Chat.ChatRemindersIntegrationTest do
  use App.DataCase, async: false  # Por causa dos fixtures

  alias App.Chat.ChatReminders
  alias App.Chat.ChatReminder
  alias App.ChatFixtures

  describe "basic reminder operations" do
    test "creates and marks reminder as done" do
      # Criar fixtures reais (usuário e tratativa)
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      # Criar lembrete
      attrs = %{
        "user_id" => user.id,
        "treaty_id" => treaty.id,
        "title" => "Teste integração",
        "description" => "Descrição do teste",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:ok, %ChatReminder{} = reminder} = ChatReminders.create_reminder(attrs)
      assert reminder.title == "Teste integração"
      assert reminder.status == "pending"

      # Marcar como feito
      assert {:ok, updated_reminder} = ChatReminders.mark_as_done(reminder.id)
      assert updated_reminder.status == "done"
      assert updated_reminder.completed_at != nil
    end

    test "gets user reminders" do
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      # Criar dois lembretes
      {:ok, _reminder1} = create_reminder(user.id, treaty.id, "Primeiro")
      {:ok, _reminder2} = create_reminder(user.id, treaty.id, "Segundo")

      # Buscar lembretes do usuário
      reminders = ChatReminders.get_user_chat_reminders(user, treaty)
      assert length(reminders) == 2
      assert Enum.any?(reminders, &(&1.title == "Primeiro"))
      assert Enum.any?(reminders, &(&1.title == "Segundo"))
    end

    test "validates scheduled_at is in future" do
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      attrs = %{
        "user_id" => user.id,
        "treaty_id" => treaty.id,
        "title" => "Teste",
        "description" => "Teste",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -1, :hour), # Passado
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = ChatReminders.create_reminder(attrs)
      assert errors[:scheduled_at] != nil
    end

    test "requires title" do
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      attrs = %{
        "user_id" => user.id,
        "treaty_id" => treaty.id,
        "title" => "",
        "description" => "Sem título",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = ChatReminders.create_reminder(attrs)
      assert errors[:title] != nil
    end

    test "gets pending reminders for notifications" do
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      # Criar lembrete passado (deve ser executado)
      past_time = DateTime.add(DateTime.utc_now(), -30, :minute)
      {:ok, _past_reminder} = create_reminder(user.id, treaty.id, "Para executar", %{
        scheduled_at: past_time
      })

      # Criar lembrete futuro (não deve ser executado)
      future_time = DateTime.add(DateTime.utc_now(), 1, :hour)
      {:ok, _future_reminder} = create_reminder(user.id, treaty.id, "Futuro", %{
        scheduled_at: future_time
      })

      # Buscar pendentes
      pending = ChatReminders.get_pending_reminders()

      # Deve ter apenas 1 lembrete pendente (o do passado)
      pending_titles = Enum.map(pending, & &1.title)
      assert "Para executar" in pending_titles
      refute "Futuro" in pending_titles
    end
  end

  describe "timezone handling" do
    test "accepts datetime in configured timezone" do
      user = App.ChatFixtures.user_fixture()
      treaty = App.ChatFixtures.treaty_fixture()

      # Criar lembrete com datetime UTC
      attrs = %{
        "user_id" => user.id,
        "treaty_id" => treaty.id,
        "title" => "Teste timezone",
        "description" => "UTC",
        "scheduled_at" => DateTime.add(DateTime.utc_now(), 1, :hour),
        "priority" => "medium",
        "notification_type" => "popup",
        "recurring_type" => "none"
      }

      assert {:ok, %ChatReminder{} = reminder} = ChatReminders.create_reminder(attrs)
      assert reminder.scheduled_at != nil
      assert reminder.status == "pending"
    end
  end

  # Helper para criar lembretes
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

    attrs = Map.merge(base_attrs, additional_attrs)

    ChatReminders.create_reminder(attrs)
  end
end
