defmodule App.SLAs do
  @moduledoc """
  Contexto para gerenciamento de SLA (Service Level Agreement) e alertas.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.SLAs.SLAAlert
  alias App.Treaties.Treaty

  @doc """
  Lista todos os alertas de SLA.
  """
  def list_sla_alerts(opts \\ []) do
    SLAAlert
    |> maybe_filter_by_status(opts[:status])
    |> maybe_filter_by_category(opts[:category])
    |> maybe_filter_by_priority(opts[:priority])
    |> maybe_order_by(opts[:order_by])
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Busca um alerta de SLA pelo ID.
  """
  def get_sla_alert(id) when is_binary(id) do
    case Repo.get(SLAAlert, id) do
      nil -> {:error, :not_found}
      alert -> {:ok, alert}
    end
  end

  @doc """
  Cria um novo alerta de SLA.
  """
  def create_sla_alert(attrs \\ %{}) do
    %SLAAlert{}
    |> SLAAlert.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza um alerta de SLA.
  """
  def update_sla_alert(%SLAAlert{} = alert, attrs) do
    alert
    |> SLAAlert.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Resolve um alerta de SLA.
  """
  def resolve_sla_alert(%SLAAlert{} = alert) do
    alert
    |> SLAAlert.changeset(%{
      status: "resolved",
      resolved_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Cancela um alerta de SLA.
  """
  def cancel_sla_alert(%SLAAlert{} = alert) do
    alert
    |> SLAAlert.changeset(%{
      status: "cancelled",
      resolved_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Verifica e cria alertas de SLA para tratativas ativas.
  """
  def check_and_create_sla_alerts do
    active_treaties = get_active_treaties_for_sla_check()

    Enum.each(active_treaties, fn treaty ->
      check_treaty_sla(treaty)
    end)
  end

  @doc """
  Verifica SLA de uma tratativa específica.
  """
  def check_treaty_sla(%Treaty{} = treaty) do
    hours_since_creation = calculate_hours_since_creation(treaty)
    sla_config = get_sla_config_for_treaty(treaty)

    cond do
      hours_since_creation >= sla_config.critical_hours ->
        create_critical_alert(treaty, sla_config, hours_since_creation)
      hours_since_creation >= sla_config.warning_hours ->
        create_warning_alert(treaty, sla_config, hours_since_creation)
      true ->
        :ok
    end
  end

  @doc """
  Obtém estatísticas de SLA para o dashboard administrativo.
  """
  def get_sla_stats do
    %{
      total_alerts: get_total_alerts_count(),
      active_alerts: get_active_alerts_count(),
      critical_alerts: get_critical_alerts_count(),
      warning_alerts: get_warning_alerts_count(),
      resolved_alerts: get_resolved_alerts_count(),
      sla_compliance_rate: get_sla_compliance_rate(),
      average_resolution_time: get_average_alert_resolution_time(),
      alerts_by_category: get_alerts_by_category(),
      alerts_by_priority: get_alerts_by_priority()
    }
  end

  @doc """
  Obtém alertas críticos que precisam de atenção imediata.
  """
  def get_critical_alerts(limit \\ 10) do
    from(a in SLAAlert,
      where: a.status == "active" and a.alert_type == "critical",
      order_by: [asc: a.alerted_at],
      limit: ^limit,
      preload: [:treaty, :created_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Obtém alertas de warning que estão próximos de se tornar críticos.
  """
  def get_warning_alerts(limit \\ 20) do
    from(a in SLAAlert,
      where: a.status == "active" and a.alert_type == "warning",
      order_by: [asc: a.alerted_at],
      limit: ^limit,
      preload: [:treaty, :created_by_user]
    )
    |> Repo.all()
  end

  # Funções privadas

  defp get_active_treaties_for_sla_check do
    from(t in Treaty,
      where: t.status == "active",
      preload: [:creator, :store]
    )
    |> Repo.all()
  end

  defp calculate_hours_since_creation(%Treaty{} = treaty) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, treaty.inserted_at, :second)
    div(diff, 3600) # Converter para horas
  end

  defp get_sla_config_for_treaty(%Treaty{} = treaty) do
    # Configurações padrão de SLA por categoria e prioridade
    base_config = case treaty.category do
      "FINANCEIRO" -> %{sla_hours: 24, warning_hours: 18, critical_hours: 20}
      "COMERCIAL" -> %{sla_hours: 48, warning_hours: 36, critical_hours: 42}
      "LOGISTICA" -> %{sla_hours: 72, warning_hours: 60, critical_hours: 66}
      _ -> %{sla_hours: 48, warning_hours: 36, critical_hours: 42}
    end

    # Ajustar baseado na prioridade
    case treaty.priority do
      "urgent" -> %{base_config | sla_hours: div(base_config.sla_hours, 2), warning_hours: div(base_config.warning_hours, 2), critical_hours: div(base_config.critical_hours, 2)}
      "high" -> %{base_config | sla_hours: div(base_config.sla_hours * 3, 4), warning_hours: div(base_config.warning_hours * 3, 4), critical_hours: div(base_config.critical_hours * 3, 4)}
      "low" -> %{base_config | sla_hours: base_config.sla_hours * 2, warning_hours: base_config.warning_hours * 2, critical_hours: base_config.critical_hours * 2}
      _ -> base_config
    end
  end

  defp create_warning_alert(treaty, sla_config, _hours_since_creation) do
    # Verificar se já existe um alerta de warning ativo
    existing_alert = get_active_alert_for_treaty(treaty.id, "warning")

    if is_nil(existing_alert) do
      create_sla_alert(%{
        treaty_id: treaty.id,
        category: treaty.category,
        priority: treaty.priority,
        sla_hours: sla_config.sla_hours,
        warning_hours: sla_config.warning_hours,
        critical_hours: sla_config.critical_hours,
        alert_type: "warning",
        created_by: treaty.created_by
      })
    end
  end

  defp create_critical_alert(treaty, sla_config, _hours_since_creation) do
    # Verificar se já existe um alerta crítico ativo
    existing_alert = get_active_alert_for_treaty(treaty.id, "critical")

    if is_nil(existing_alert) do
      create_sla_alert(%{
        treaty_id: treaty.id,
        category: treaty.category,
        priority: treaty.priority,
        sla_hours: sla_config.sla_hours,
        warning_hours: sla_config.warning_hours,
        critical_hours: sla_config.critical_hours,
        alert_type: "critical",
        created_by: treaty.created_by
      })
    end
  end

  defp get_active_alert_for_treaty(treaty_id, alert_type) do
    from(a in SLAAlert,
      where: a.treaty_id == ^treaty_id and a.status == "active" and a.alert_type == ^alert_type
    )
    |> Repo.one()
  end

  # Funções de filtro e ordenação
  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status), do: from(a in query, where: a.status == ^status)

  defp maybe_filter_by_category(query, nil), do: query
  defp maybe_filter_by_category(query, category), do: from(a in query, where: a.category == ^category)

  defp maybe_filter_by_priority(query, nil), do: query
  defp maybe_filter_by_priority(query, priority), do: from(a in query, where: a.priority == ^priority)

  defp maybe_order_by(query, :alerted_at), do: from(a in query, order_by: [desc: a.alerted_at])
  defp maybe_order_by(query, :priority), do: from(a in query, order_by: [asc: a.priority])
  defp maybe_order_by(query, :category), do: from(a in query, order_by: [asc: a.category])
  defp maybe_order_by(query, _), do: from(a in query, order_by: [desc: a.inserted_at])

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(a in query, limit: ^limit)

  # Funções de estatísticas
  defp get_total_alerts_count do
    from(a in SLAAlert, select: count())
    |> Repo.one() || 0
  end

  defp get_active_alerts_count do
    from(a in SLAAlert, where: a.status == "active", select: count())
    |> Repo.one() || 0
  end

  defp get_critical_alerts_count do
    from(a in SLAAlert, where: a.status == "active" and a.alert_type == "critical", select: count())
    |> Repo.one() || 0
  end

  defp get_warning_alerts_count do
    from(a in SLAAlert, where: a.status == "active" and a.alert_type == "warning", select: count())
    |> Repo.one() || 0
  end

  defp get_resolved_alerts_count do
    from(a in SLAAlert, where: a.status == "resolved", select: count())
    |> Repo.one() || 0
  end

  defp get_sla_compliance_rate do
    total_treaties = from(t in Treaty, where: t.status == "closed", select: count()) |> Repo.one() || 0
    breached_treaties = from(a in SLAAlert, where: a.status == "resolved" and a.alert_type == "critical", select: count()) |> Repo.one() || 0

    if total_treaties > 0 do
      compliance_rate = ((total_treaties - breached_treaties) / total_treaties) * 100
      Float.round(compliance_rate, 2)
    else
      100.0
    end
  end

  defp get_average_alert_resolution_time do
    from(a in SLAAlert,
      where: a.status == "resolved" and not is_nil(a.resolved_at),
      select: avg(fragment("EXTRACT(EPOCH FROM (? - ?))", a.resolved_at, a.alerted_at))
    )
    |> Repo.one()
    |> case do
      nil -> 0
      seconds -> Float.round(seconds / 3600, 2) # Converter para horas
    end
  end

  defp get_alerts_by_category do
    from(a in SLAAlert,
      group_by: a.category,
      select: %{
        category: a.category,
        count: count()
      },
      order_by: [asc: a.category]
    )
    |> Repo.all()
  end

  defp get_alerts_by_priority do
    from(a in SLAAlert,
      group_by: a.priority,
      select: %{
        priority: a.priority,
        count: count()
      },
      order_by: [asc: a.priority]
    )
    |> Repo.all()
  end
end
