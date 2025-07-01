defmodule App.Auth.SecurityLogger do
  @moduledoc """
  Security logging system for authentication events.

  Provides structured logging of all security-related events including
  login attempts, password changes, token operations, and suspicious activities.
  """

  require Logger

  alias App.Accounts.User
  alias App.Schemas.SecurityEvent
  alias App.Repo

  @log_levels %{
    login_success: :info,
    login_failed: :warning,
    logout: :info,
    token_refresh: :info,
    token_refresh_failed: :warning,
    password_changed: :info,
    password_change_failed: :warning,
    account_locked: :warning,
    suspicious_activity: :error,
    brute_force_detected: :error
  }

  def log_event(event_type, user \\ nil, metadata \\ %{}) do
    log_level = Map.get(@log_levels, event_type, :info)

    log_data = %{
      event_type: event_type,
      timestamp: DateTime.utc_now(),
      user_id: get_user_id(user),
      username: get_username(user),
      session_id: Map.get(metadata, :session_id),
      ip_address: Map.get(metadata, :ip_address),
      user_agent: Map.get(metadata, :user_agent),
      metadata: metadata
    }

    # Log to standard Logger
    Logger.log(log_level, format_log_message(event_type, log_data), log_data)

    # Store in database for audit trail
    store_security_event(log_data)

    # Check for suspicious patterns
    check_suspicious_patterns(event_type, log_data)
  end

  def get_security_events(filters \\ %{}, opts \\ []) do
    import Ecto.Query

    query = from(e in SecurityEvent, order_by: [desc: e.timestamp])

    query
    |> apply_filters(filters)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  def get_user_activity(user_id, from_date \\ nil, to_date \\ nil) do
    import Ecto.Query

    query = from(e in SecurityEvent,
      where: e.user_id == ^user_id,
      order_by: [desc: e.timestamp]
    )

    query
    |> maybe_filter_date_range(from_date, to_date)
    |> Repo.all()
  end

  def generate_security_report(from_date, to_date) do
    # This would generate a comprehensive security report
    # For now, returning basic structure
    %{
      period: %{from: from_date, to: to_date},
      summary: %{
        total_events: 0,
        login_attempts: 0,
        failed_logins: 0,
        successful_logins: 0,
        locked_accounts: 0,
        suspicious_activities: 0
      },
      top_events: [],
      top_ip_addresses: [],
      alerts: []
    }
  end

  # Private functions

  defp get_user_id(%User{id: id}), do: id
  defp get_user_id(_), do: nil

  defp get_username(%User{username: username}), do: username
  defp get_username(_), do: nil

  defp format_log_message(:login_success, %{username: username, ip_address: ip}) do
    "User #{username} logged in successfully from #{ip}"
  end

  defp format_log_message(:login_failed, %{username: username, ip_address: ip}) do
    "Failed login attempt for user #{username} from #{ip}"
  end

  defp format_log_message(:logout, %{username: username, ip_address: ip}) do
    "User #{username} logged out from #{ip}"
  end

  defp format_log_message(:token_refresh, %{username: username, ip_address: ip}) do
    "Token refreshed for user #{username} from #{ip}"
  end

  defp format_log_message(:token_refresh_failed, %{ip_address: ip}) do
    "Token refresh failed from #{ip}"
  end

  defp format_log_message(:password_changed, %{username: username, ip_address: ip}) do
    "Password changed for user #{username} from #{ip}"
  end

  defp format_log_message(:password_change_failed, %{username: username, ip_address: ip}) do
    "Failed password change attempt for user #{username} from #{ip}"
  end

  defp format_log_message(:account_locked, %{username: username, ip_address: ip}) do
    "Account locked for user #{username} due to suspicious activity from #{ip}"
  end

  defp format_log_message(event_type, %{username: username, ip_address: ip}) do
    "Security event #{event_type} for user #{username} from #{ip}"
  end

  defp format_log_message(event_type, _log_data) do
    "Security event: #{event_type}"
  end

  defp store_security_event(log_data) do
    event_attrs = %{
      event_type: to_string(log_data.event_type),
      user_id: log_data.user_id,
      username: log_data.username,
      session_id: log_data.session_id,
      ip_address: log_data.ip_address,
      user_agent: log_data.user_agent,
      success: determine_success(log_data.event_type),
      failure_reason: get_failure_reason(log_data),
      metadata: sanitize_metadata(log_data.metadata),
      severity: determine_severity(log_data.event_type),
      timestamp: log_data.timestamp
    }

    case SecurityEvent.create_changeset(event_attrs) |> Repo.insert() do
      {:ok, _event} -> :ok
      {:error, changeset} ->
        Logger.error("Failed to store security event", %{
          errors: changeset.errors,
          event_type: log_data.event_type
        })
        :error
    end
  rescue
    exception ->
      Logger.error("Exception storing security event", %{
        exception: exception,
        event_type: log_data.event_type
      })
      :error
  end

  defp determine_success(event_type) do
    case event_type do
      :login_success -> true
      :logout -> true
      :token_refresh -> true
      :password_changed -> true
      :password_reset_completed -> true
      _ -> false
    end
  end

  defp get_failure_reason(log_data) do
    case log_data.event_type do
      :login_failed -> Map.get(log_data.metadata, :reason, "invalid_credentials")
      :token_refresh_failed -> Map.get(log_data.metadata, :reason, "invalid_token")
      :password_change_failed -> Map.get(log_data.metadata, :reason, "validation_failed")
      :password_reset_failed -> Map.get(log_data.metadata, :reason, "reset_failed")
      :account_locked -> Map.get(log_data.metadata, :reason, "excessive_attempts")
      _ -> nil
    end
  end

  defp sanitize_metadata(metadata) when is_map(metadata) do
    # Remove sensitive data from metadata
    metadata
    |> Map.delete(:password)
    |> Map.delete(:token)
    |> Map.delete(:refresh_token)
  end

  defp sanitize_metadata(metadata), do: metadata

  defp determine_severity(event_type) do
    case event_type do
      :brute_force_detected -> "critical"
      :suspicious_activity -> "error"
      :account_locked -> "warning"
      :login_failed -> "warning"
      :token_refresh_failed -> "warning"
      :password_change_failed -> "warning"
      :password_reset_failed -> "warning"
      _ -> "info"
    end
  end

  defp check_suspicious_patterns(event_type, log_data) do
    case event_type do
      :login_failed ->
        check_brute_force_pattern(log_data)
      :login_success ->
        check_unusual_login_pattern(log_data)
      _ -> :ok
    end
  end

  defp check_brute_force_pattern(%{ip_address: ip_address} = _log_data) when not is_nil(ip_address) do
    # Check for multiple failed attempts from same IP
    recent_failures = count_recent_failures_from_ip(ip_address)

    if recent_failures >= 5 do
      log_event(:brute_force_detected, nil, %{
        ip_address: ip_address,
        attempts: recent_failures,
        detection_time: DateTime.utc_now()
      })
    end
  end

  defp check_brute_force_pattern(_), do: :ok

  defp check_unusual_login_pattern(%{user_id: user_id, ip_address: ip_address} = _log_data)
    when not is_nil(user_id) and not is_nil(ip_address) do

    # Check if user is logging in from a new IP
    if new_ip_for_user?(user_id, ip_address) do
      log_event(:suspicious_activity, %{id: user_id}, %{
        ip_address: ip_address,
        reason: "login_from_new_ip",
        detection_time: DateTime.utc_now()
      })
    end
  end

  defp check_unusual_login_pattern(_), do: :ok

  defp apply_filters(query, filters) do
    import Ecto.Query

    Enum.reduce(filters, query, fn
      {:event_type, type}, q -> where(q, [e], e.event_type == ^type)
      {:user_id, user_id}, q -> where(q, [e], e.user_id == ^user_id)
      {:ip_address, ip}, q -> where(q, [e], e.ip_address == ^ip)
      {:severity, severity}, q -> where(q, [e], e.severity == ^severity)
      {:success, success}, q -> where(q, [e], e.success == ^success)
      {:from_date, date}, q -> where(q, [e], e.timestamp >= ^date)
      {:to_date, date}, q -> where(q, [e], e.timestamp <= ^date)
      _, q -> q
    end)
  end

  defp apply_pagination(query, opts) do
    import Ecto.Query

    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp maybe_filter_date_range(query, nil, nil), do: query
  defp maybe_filter_date_range(query, from_date, nil) do
    import Ecto.Query
    where(query, [e], e.timestamp >= ^from_date)
  end
  defp maybe_filter_date_range(query, nil, to_date) do
    import Ecto.Query
    where(query, [e], e.timestamp <= ^to_date)
  end
  defp maybe_filter_date_range(query, from_date, to_date) do
    import Ecto.Query
    where(query, [e], e.timestamp >= ^from_date and e.timestamp <= ^to_date)
  end

  defp count_recent_failures_from_ip(ip_address) do
    import Ecto.Query

    cutoff = DateTime.add(DateTime.utc_now(), -300, :second)

    from(e in SecurityEvent,
      where: e.event_type == "login_failed" and
             e.ip_address == ^ip_address and
             e.timestamp >= ^cutoff,
      select: count(e.id)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp new_ip_for_user?(user_id, ip_address) do
    import Ecto.Query

    exists = from(e in SecurityEvent,
      where: e.user_id == ^user_id and
             e.ip_address == ^ip_address and
             e.event_type == "login_success",
      limit: 1
    )
    |> Repo.exists?()

    not exists
  end
end
