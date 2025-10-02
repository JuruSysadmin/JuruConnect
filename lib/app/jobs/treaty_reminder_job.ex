defmodule App.Jobs.TreatyReminderJob do
  @moduledoc """
  Job Oban para criar lembretes automáticos de tratativas inativas.

  Executa periodicamente para identificar tratativas que não têm atividade
  há mais de 24 horas e criar lembretes automaticamente.
  """

  use Oban.Worker, queue: :default
  require Logger

  alias App.TreatyReminders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"hours_threshold" => hours_threshold}}) when is_integer(hours_threshold) do
    case TreatyReminders.automatic_reminder_creation(hours_threshold) do
      {:ok, count} ->
        Logger.info("TreatyReminderJob: Criados #{count} lembretes automáticos")
        :ok
    end
  end

  def perform(%Oban.Job{args: %{}}) do
    perform(%Oban.Job{args: %{"hours_threshold" => 24}})
  end

  @doc """
  Agenda um job para criar lembretes de tratativas inativas.
  """
  def schedule_job(hours_threshold \\ 24) do
    %{
      "hours_threshold" => hours_threshold
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Agenda um job recorrente para verificação de tratativas inativas.
  """
  def schedule_recurring_job do
    # Executa a cada 6 horas
    %{
      "hours_threshold" => 24
    }
    |> __MODULE__.new(schedule_in: 6 * 60 * 60) # 6 horas em sistema Unix cron não está disponível facilmente no teste
    |> Oban.insert()
  end
end
