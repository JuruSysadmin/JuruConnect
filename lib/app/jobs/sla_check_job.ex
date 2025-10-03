defmodule App.Jobs.SLACheckJob do
  @moduledoc """
  Job agendado para verificar SLA de tratativas e criar alertas automaticamente.
  """

  use Oban.Worker, queue: :sla_monitoring

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Verificar e criar alertas de SLA
    App.SLAs.check_and_create_sla_alerts()

    # Enviar notificações para alertas críticos
    send_critical_alerts_notifications()

    # Escalar alertas que estão há muito tempo ativos
    escalate_old_alerts()

    :ok
  end

  @doc """
  Agenda o job de verificação de SLA para execução periódica.
  """
  def schedule_sla_check do
    %{
      "scheduled_at" => DateTime.add(DateTime.utc_now(), 15 * 60, :second) # 15 minutos
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Agenda verificação imediata de SLA.
  """
  def schedule_immediate_sla_check do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # Funções privadas

  defp send_critical_alerts_notifications do
    critical_alerts = App.SLAs.get_critical_alerts(50)

    Enum.each(critical_alerts, fn alert ->
      # Notificar administradores sobre alertas críticos
      notify_admins_about_critical_alert(alert)

      # Notificar usuários relacionados à tratativa
      notify_treaty_users_about_critical_alert(alert)
    end)
  end

  defp escalate_old_alerts do
    # Buscar alertas críticos que estão ativos há mais de 2 horas
    old_critical_alerts = get_old_critical_alerts()

    Enum.each(old_critical_alerts, fn alert ->
      escalate_alert(alert)
    end)
  end

  defp get_old_critical_alerts do
    two_hours_ago = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)

    import Ecto.Query

    from(a in App.SLAs.SLAAlert,
      where: a.status == "active" and
             a.alert_type == "critical" and
             a.alerted_at < ^two_hours_ago and
             is_nil(a.escalated_at),
      preload: [:treaty, :created_by_user]
    )
    |> App.Repo.all()
  end

  defp escalate_alert(alert) do
    # Marcar como escalado
    App.SLAs.update_sla_alert(alert, %{
      escalated_at: DateTime.utc_now(),
      escalated_to: "management"
    })

    # Enviar notificação de escalação
    notify_escalation(alert)
  end

  defp notify_admins_about_critical_alert(alert) do
    admins = App.Accounts.get_users_by_role("admin")

    Enum.each(admins, fn admin ->
      App.Notifications.send_desktop_notification(admin, %{
        id: "sla-critical-#{alert.id}",
        text: "ALERTA CRÍTICO: Tratativa #{alert.treaty.treaty_code} está em risco de SLA",
        sender_name: "Sistema SLA",
        treaty_id: alert.treaty_id,
        tipo: "sla_alert"
      }, :sla_critical)
    end)
  end

  defp notify_treaty_users_about_critical_alert(alert) do
    # Notificar usuários que têm acesso à tratativa
    topic = "treaty:#{alert.treaty_id}"
    presences = AppWeb.Presence.list(topic)

    user_ids = presences
    |> Map.values()
    |> Enum.flat_map(fn %{metas: metas} ->
      Enum.map(metas, fn %{user_id: user_id} -> user_id end)
    end)
    |> Enum.filter(&(&1 != "anonymous" && &1 != nil))
    |> Enum.uniq()

    Enum.each(user_ids, fn user_id ->
      case App.Accounts.get_user(user_id) do
        nil -> :ok
        user ->
          App.Notifications.send_desktop_notification(user, %{
            id: "sla-warning-#{alert.id}",
            text: "ATENÇÃO: Tratativa #{alert.treaty.treaty_code} está próxima do prazo de SLA",
            sender_name: "Sistema SLA",
            treaty_id: alert.treaty_id,
            tipo: "sla_warning"
          }, :sla_warning)
      end
    end)
  end

  defp notify_escalation(alert) do
    # Notificar gestores sobre escalação
    managers = App.Accounts.get_users_by_role("manager")

    Enum.each(managers, fn manager ->
      App.Notifications.send_desktop_notification(manager, %{
        id: "sla-escalation-#{alert.id}",
        text: "ESCALAÇÃO: Tratativa #{alert.treaty.treaty_code} foi escalada para gestão",
        sender_name: "Sistema SLA",
        treaty_id: alert.treaty_id,
        tipo: "sla_escalation"
      }, :sla_escalation)
    end)
  end
end
