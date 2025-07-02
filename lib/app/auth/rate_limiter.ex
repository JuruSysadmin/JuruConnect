defmodule App.Auth.RateLimiter do
  @moduledoc """
  Sistema de rate limiting persistente usando PostgreSQL.

  Implementa controle de tentativas de login e bloqueios automáticos
  armazenados no banco de dados, garantindo que os limites persistam
  mesmo após restarts do servidor.

  ## Funcionalidades

  - Rate limiting por IP e username
  - Bloqueios automáticos por tentativas excessivas
  - Bloqueios manuais por administradores
  - Cleanup automático de dados expirados
  - Estatísticas em tempo real
  - Detecção de captcha necessário

  ## Configurações

  - Máximo 10 tentativas por IP
  - Máximo 5 tentativas por usuário
  - Bloqueios duram 15 minutos
  - Janela de tentativas: 60 minutos
  """

  require Logger
  import Ecto.Query

  alias App.Auth.SecurityLogger
  alias App.Repo
  alias App.Schemas.{ActiveBlock, LoginAttempt}

  @max_attempts_per_ip 10
  @max_attempts_per_user 5
  @lockout_duration_minutes 15
  @attempt_window_minutes 60

  @type check_result :: :allowed | {:rate_limited, integer()} | :captcha_required

  @spec check_login_attempt(String.t(), String.t()) :: check_result()
  def check_login_attempt(username, ip_address) do
    now = DateTime.utc_now()

    cond do
      blocked?("ip", ip_address, now) ->
        remaining = get_block_remaining("ip", ip_address, now)
        {:rate_limited, remaining}

      blocked?("username", username, now) ->
        remaining = get_block_remaining("username", username, now)
        {:rate_limited, remaining}

      true ->
        ip_count = get_attempt_count("ip", ip_address, now)
        user_count = get_attempt_count("username", username, now)

        cond do
          ip_count >= @max_attempts_per_ip ->
            {:rate_limited, @lockout_duration_minutes * 60}

          user_count >= @max_attempts_per_user ->
            {:rate_limited, @lockout_duration_minutes * 60}

          ip_count >= 7 or user_count >= 3 ->
            :captcha_required

          true ->
            :allowed
        end
    end
  end

  @spec record_failed_attempt(String.t(), String.t()) :: :ok
  def record_failed_attempt(username, ip_address) do
    now = DateTime.utc_now()

    record_attempt("ip", ip_address, now)
    record_attempt("username", username, now)

    ip_count = get_attempt_count("ip", ip_address, now)
    user_count = get_attempt_count("username", username, now)

    maybe_create_block("ip", ip_address, ip_count, @max_attempts_per_ip, now)
    maybe_create_block("username", username, user_count, @max_attempts_per_user, now)

    SecurityLogger.log_event(:login_failed, nil, %{
      username: username,
      ip_address: ip_address,
      ip_attempts: ip_count,
      user_attempts: user_count
    })

    :ok
  end

  @spec reset_attempts(String.t(), String.t()) :: :ok
  def reset_attempts(username, ip_address) do
    delete_attempts("ip", ip_address)
    delete_attempts("username", username)

    Logger.info("Reset auth attempts", %{
      username: username,
      ip_address: ip_address
    })

    :ok
  end

  @spec get_stats() :: map()
  def get_stats do
    now = DateTime.utc_now()

    %{
      active_blocks: count_active_blocks(now),
      total_login_attempts: count_total_attempts(),
      recent_attempts: count_recent_attempts(now),
      blocked_ips: count_blocked_by_type("ip", now),
      blocked_users: count_blocked_by_type("username", now)
    }
  end

  @spec manual_block(String.t(), String.t(), String.t(), integer()) :: :ok | {:error, term()}
  def manual_block(identifier, identifier_type, reason, duration_minutes \\ @lockout_duration_minutes) do
    expires_at = DateTime.add(DateTime.utc_now(), duration_minutes * 60, :second)

    block_attrs = %{
      identifier: identifier,
      identifier_type: identifier_type,
      reason: reason,
      expires_at: expires_at,
      metadata: %{manual: true, duration_minutes: duration_minutes}
    }

    case ActiveBlock.create_changeset(block_attrs) |> Repo.insert() do
      {:ok, _block} ->
        Logger.warning("Manual block created", %{
          identifier: identifier,
          identifier_type: identifier_type,
          reason: reason,
          duration_minutes: duration_minutes
        })
        :ok

      {:error, changeset} ->
        Logger.error("Failed to create manual block", %{
          identifier: identifier,
          errors: changeset.errors
        })
        {:error, changeset}
    end
  end

  @spec unblock(String.t(), String.t()) :: :ok
  def unblock(identifier, identifier_type) do
    from(b in ActiveBlock,
      where: b.identifier == ^identifier and b.identifier_type == ^identifier_type
    )
    |> Repo.delete_all()

    Logger.info("Manual unblock", %{
      identifier: identifier,
      identifier_type: identifier_type
    })

    :ok
  end

  @spec cleanup_expired() :: {integer(), integer()}
  def cleanup_expired do
    now = DateTime.utc_now()
    deleted_attempts = cleanup_expired_attempts(now)
    deleted_blocks = cleanup_expired_blocks(now)

    if deleted_attempts > 0 or deleted_blocks > 0 do
      Logger.info("Cleaned up expired data", %{
        deleted_attempts: deleted_attempts,
        deleted_blocks: deleted_blocks
      })
    end

    {deleted_attempts, deleted_blocks}
  end

  defp blocked?(identifier_type, identifier, now) do
    from(b in ActiveBlock,
      where: b.identifier_type == ^identifier_type and
             b.identifier == ^identifier and
             b.expires_at > ^now
    )
    |> Repo.exists?()
  end

  defp get_block_remaining(identifier_type, identifier, now) do
    case from(b in ActiveBlock,
           where: b.identifier_type == ^identifier_type and
                  b.identifier == ^identifier and
                  b.expires_at > ^now,
           select: b.expires_at,
           limit: 1
         ) |> Repo.one() do
      nil -> 0
      expires_at -> DateTime.diff(expires_at, now, :second)
    end
  end

  defp get_attempt_count(identifier_type, identifier, now) do
    cutoff = DateTime.add(now, -@attempt_window_minutes * 60, :second)

    from(a in LoginAttempt,
      where: a.identifier_type == ^identifier_type and
             a.identifier == ^identifier and
             a.last_attempt_at > ^cutoff,
      select: a.attempt_count
    )
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  defp record_attempt(identifier_type, identifier, now) do
    cutoff = DateTime.add(now, -@attempt_window_minutes * 60, :second)
    expires_at = DateTime.add(now, @attempt_window_minutes * 60, :second)

    from(a in LoginAttempt,
      where: a.identifier_type == ^identifier_type and a.identifier == ^identifier
    )
    |> Repo.one()
    |> case do
      nil ->
        LoginAttempt.create_changeset(%{
          identifier: identifier,
          identifier_type: identifier_type,
          attempt_count: 1,
          expires_at: expires_at
        })
        |> Repo.insert()

      existing_attempt ->
        if DateTime.compare(existing_attempt.last_attempt_at, cutoff) == :gt do
          existing_attempt
          |> LoginAttempt.changeset(%{
            attempt_count: existing_attempt.attempt_count + 1,
            last_attempt_at: now,
            expires_at: expires_at
          })
          |> Repo.update()
        else
          existing_attempt
          |> LoginAttempt.changeset(%{
            attempt_count: 1,
            first_attempt_at: now,
            last_attempt_at: now,
            expires_at: expires_at
          })
          |> Repo.update()
        end
    end
  end

  defp delete_attempts(identifier_type, identifier) do
    from(a in LoginAttempt,
      where: a.identifier_type == ^identifier_type and a.identifier == ^identifier
    )
    |> Repo.delete_all()
  end

  defp maybe_create_block(identifier_type, identifier, count, max_attempts, now) do
    if count >= max_attempts do
      expires_at = DateTime.add(now, @lockout_duration_minutes * 60, :second)

      ActiveBlock.create_changeset(%{
        identifier: identifier,
        identifier_type: identifier_type,
        reason: "excessive_login_attempts",
        expires_at: expires_at,
        metadata: %{
          attempt_count: count,
          auto_blocked: true
        }
      })
      |> Repo.insert()

      Logger.warning("Auto-block created", %{
        identifier: identifier,
        identifier_type: identifier_type,
        attempts: count,
        expires_at: expires_at
      })
    end
  end

  defp count_active_blocks(now) do
    from(b in ActiveBlock, where: b.expires_at > ^now, select: count(b.id))
    |> Repo.one() || 0
  end

  defp count_total_attempts do
    from(a in LoginAttempt, select: count(a.id))
    |> Repo.one() || 0
  end

  defp count_recent_attempts(now) do
    cutoff = DateTime.add(now, -300, :second)

    from(a in LoginAttempt,
      where: a.last_attempt_at > ^cutoff,
      select: count(a.id)
    )
    |> Repo.one() || 0
  end

  defp count_blocked_by_type(identifier_type, now) do
    from(b in ActiveBlock,
      where: b.identifier_type == ^identifier_type and b.expires_at > ^now,
      select: count(b.id)
    )
    |> Repo.one() || 0
  end

  defp cleanup_expired_attempts(now) do
    from(a in LoginAttempt, where: a.expires_at <= ^now)
    |> Repo.delete_all()
    |> elem(0)
  end

  defp cleanup_expired_blocks(now) do
    from(b in ActiveBlock, where: b.expires_at <= ^now)
    |> Repo.delete_all()
    |> elem(0)
  end
end
