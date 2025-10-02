defmodule App.GlobalReminders do
  @moduledoc """
  O módulo GlobalReminders oferece funcionalidades para criar e gerenciar lembretes globais
  com agendamento de horário, recorrência e diferentes tipos de notificação.

  Permite que usuários criem lembretes pessoais com:
  - Agendamento de data/hora específica
  - Tipos de notificação (popup, email, sms)
  - Recorrência (diária, semanal, mensal)
  - Prioridades (baixa, média, alta, urgente)
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.GlobalReminders.GlobalReminder

  @doc """
  Cria um novo lembrete global.

  ## Exemplos

      iex> create_reminder(%{field: value})
      {:ok, %GlobalReminder{}}

      iex> create_reminder(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_reminder(attrs \\ %{}) do
    %GlobalReminder{}
    |> GlobalReminder.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retorna a lista de lembretes de um usuário específico.
  """
  def get_user_reminders(user_or_id) do
    user_id = get_user_id(user_or_id)

    from(r in GlobalReminder,
      where: r.user_id == ^user_id and r.status != "deleted",
      order_by: [asc: r.scheduled_at]
    )
    |> Repo.all()
  end

  @doc """
  Retorna lembretes filtrados por status.
  """
  def get_user_reminders(user_or_id, :pending) do
    user_id = get_user_id(user_or_id)

    from(r in GlobalReminder,
      where: r.user_id == ^user_id and r.status == "pending",
      order_by: [asc: r.scheduled_at]
    )
    |> Repo.all()
  end

  def get_user_reminders(user_or_id, :done) do
    user_id = get_user_id(user_or_id)

    from(r in GlobalReminder,
      where: r.user_id == ^user_id and r.status == "done",
      order_by: [desc: r.completed_at]
    )
    |> Repo.all()
  end

  @doc """
  Encontra lembretes pendentes que devem ser executados agora.

  Busca lembretes com status 'pending' onde a data agendada é menor ou igual ao momento atual.
  """
  def get_pending_reminders do
    now = DateTime.utc_now()

    from(r in GlobalReminder,
      where: r.status == "pending" and r.scheduled_at <= ^now,
      order_by: [asc: r.scheduled_at]
    )
    |> Repo.all()
  end

  @doc """
  Atualiza dados de um lembrete específico.

  ## Exemplos

      iex> update_reminder(reminder, %{field: new_value})
      {:ok, %GlobalReminder{}}

      iex> update_reminder(bad_id, %{field: new_value})
      {:error, :not_found}

  """
  def update_reminder(id, attrs) do
    reminder = Repo.get(GlobalReminder, id)

    if reminder && reminder.status != "deleted" do
      reminder
      |> GlobalReminder.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Marca um lembrete como realizado.

  Atualiza o status para 'done' e registra o timestamp de conclusão.

  ## Exemplos

      iex> mark_as_done(reminder)
      {:ok, %GlobalReminder{}}

      iex> mark_as_done(bad_id)
      {:error, :not_found}

  """
  def mark_as_done(id) do
    reminder = Repo.get(GlobalReminder, id)

    if reminder && reminder.status == "pending" do
      reminder
      |> GlobalReminder.mark_done_changeset()
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Remove um lembrete através de soft deletion.

  ## Exemplos

      iex> delete_reminder(reminder)
      {:ok, %GlobalReminder{}}

      iex> delete_reminder(bad_id)
      {:error, :not_found}

  """
  def delete_reminder(id) do
    reminder = Repo.get(GlobalReminder, id)

    if reminder && reminder.status != "deleted" do
      reminder
      |> GlobalReminder.delete_changeset()
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Cria próxima ocorrência de lembrete recorrente.

  Calcula a próxima data baseada no tipo de recorrência e cria novo lembrete.
  """
  def create_next_recurring(reminder_id) do
    reminder = Repo.get(GlobalReminder, reminder_id)

    if reminder && reminder.recurring_type != "none" do
      next_date = calculate_next_recurring_date(reminder.scheduled_at, reminder.recurring_type)

      %GlobalReminder{}
      |> GlobalReminder.create_changeset(%{
        user_id: reminder.user_id,
        title: reminder.title,
        description: reminder.description,
        scheduled_at: next_date,
        notification_type: reminder.notification_type,
        recurring_type: reminder.recurring_type,
        priority: reminder.priority
      })
      |> Repo.insert()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Calcula estatísticas dos lembretes do usuário.

  Retorna contadores de lembrete por status e outras métricas úteis.
  """
  def get_reminder_stats(user_id) do
    reminders = from(r in GlobalReminder,
      where: r.user_id == ^user_id
    ) |> Repo.all()

    %{
      total_reminders: length(reminders),
      pending_reminders: Enum.count(reminders, &(&1.status == "pending")),
      completed_reminders: Enum.count(reminders, &(&1.status == "done")),
      deleted_reminders: Enum.count(reminders, &(&1.status == "deleted")),
      high_priority_reminders: Enum.count(reminders, &(&1.priority == "high" or &1.priority == "urgent")),
      recurring_reminders: Enum.count(reminders, &(&1.recurring_type != "none")),
      reminders_today: Enum.count(reminders, fn r ->
        date = DateTime.to_date(r.scheduled_at)
        DateTime.to_date(DateTime.utc_now()) == date
      end)
    }
  end

  @doc """
  Busca lembretes por título ou descrição.

  Usa busca case-insensitive no título e descrição.
  """
  def search_reminders(user_id, search_term) when is_binary(search_term) do
    from(r in GlobalReminder,
      where: r.user_id == ^user_id and r.status != "deleted",
      where: ilike(r.title, ^"%#{search_term}%") or ilike(r.description, ^"%#{search_term}%"),
      order_by: [asc: r.scheduled_at]
    )
    |> Repo.all()
  end

  @doc """
  Retorna um lembrete específico por ID.
  """
  def get_reminder!(id), do: Repo.get!(GlobalReminder, id)

  @doc """
  Retorna um lembrete específico por ID (versão safe).
  """
  def get_reminder(id), do: Repo.get(GlobalReminder, id)

  # Função auxiliar para lidar com user object ou ID
  defp get_user_id(%{id: id}), do: id
  defp get_user_id(id) when is_binary(id), do: id

  # Função para calcular próxima data recorrente
  defp calculate_next_recurring_date(current_date, "daily") do
    DateTime.add(current_date, 1, :day)
  end

  defp calculate_next_recurring_date(current_date, "weekly") do
    DateTime.add(current_date, 7, :day)
  end

  defp calculate_next_recurring_date(current_date, "monthly") do
    DateTime.add(current_date, 30, :day)
  end

  defp calculate_next_recurring_date(current_date, "none"), do: current_date
end
