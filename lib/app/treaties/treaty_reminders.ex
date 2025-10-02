defmodule App.TreatyReminders do
  @moduledoc """
  Módulo responsável por gerenciar lembretes automáticos de tratativas inativas.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Treaties.{Treaty, TreatyReminder}
  alias App.Chat.Message

  @doc """
  Busca tratativas que não têm atividade há mais de X horas.
  """
  def get_inactive_treaties(hours_threshold) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-hours_threshold, :hour)

    # Subquery para encontrar a última mensagem de cada tratativa
    last_message_subquery =
      from(m in Message,
        select: %{treaty_id: m.treaty_id, last_message_at: max(m.inserted_at)},
        group_by: m.treaty_id
      )

    # Query principal para encontrar tratativas inativas
    from(t in Treaty,
      left_join: lm in subquery(last_message_subquery),
      on: t.treaty_code == lm.treaty_id,
      where: t.status == "active" and
             (lm.last_message_at < ^cutoff_time or is_nil(lm.last_message_at)),
      order_by: [asc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Cria um lembrete para uma tratativa.
  """
  def create_reminder(treaty_id, message) do
    attrs = %{
      treaty_id: treaty_id,
      message: message
    }

    %TreatyReminder{}
    |> TreatyReminder.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marca um lembrete como notificado.
  """
  def mark_as_notified(reminder_id) do
    case Repo.get(TreatyReminder, reminder_id) do
      nil ->
        {:error, :not_found}

      reminder ->
        changeset = Ecto.Changeset.change(reminder,
          status: "notified",
          notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
        Repo.update(changeset)
    end
  end

  @doc """
  Busca lembretes pendentes.
  """
  def get_pending_reminders do
    from(r in TreatyReminder,
      where: r.status == "pending",
      order_by: [asc: r.inserted_at],
      preload: [:treaty]
    )
    |> Repo.all()
  end

  @doc """
  Cria lembretes automaticamente para tratativas inativas.
  """
  def automatic_reminder_creation(hours_threshold) do
    inactive_treaties = get_inactive_treaties(hours_threshold)
    count = Enum.reduce(inactive_treaties, 0, fn treaty, acc ->
      # Verificar se já existe um lembrete pendente para esta tratativa
      existing_reminder = from(r in TreatyReminder,
        where: r.treaty_id == ^treaty.id and r.status == "pending"
      ) |> Repo.one()

      if existing_reminder do
        acc
      else
        message = "Tratativa inativa há mais de #{hours_threshold} horas"
        case create_reminder(treaty.id, message) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end
    end)

    {:ok, count}
  end

  @doc """
  Retorna estatísticas dos lembretes.
  """
  def get_reminder_stats do
    total_reminders = from(r in TreatyReminder, select: count()) |> Repo.one() || 0
    pending_reminders = from(r in TreatyReminder,
      where: r.status == "pending",
      select: count()
    ) |> Repo.one() || 0
    notified_reminders = from(r in TreatyReminder,
      where: r.status == "notified",
      select: count()
    ) |> Repo.one() || 0

    reminder_rate = if total_reminders > 0 do
      Float.round((pending_reminders / total_reminders) * 100, 2)
    else
      0.0
    end

    %{
      total_reminders: total_reminders,
      pending_reminders: pending_reminders,
      notified_reminders: notified_reminders,
      reminder_rate: reminder_rate
    }
  end

  @doc """
  List all reminders for a specific treaty.

  ## Examples

      iex> get_treaty_reminders(treaty_id)
      [%TreatyReminder{}, ...]

  """
  def get_treaty_reminders(treaty_id) do
    from(r in TreatyReminder,
      where: r.treaty_id == ^treaty_id,
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
  end
end
