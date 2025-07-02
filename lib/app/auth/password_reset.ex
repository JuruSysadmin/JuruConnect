defmodule App.Auth.PasswordReset do
  @moduledoc """
  Sistema de recuperação de senha segura.

  Gerencia tokens de reset de senha, validação de tempo de expiração,
  e processo seguro de redefinição de senhas.
  """

  use GenServer
  require Logger

  alias App.Accounts
  alias App.Auth.SecurityLogger
  alias App.Mailer
  alias App.Email

  @reset_token_ttl_hours 2
  @max_reset_attempts_per_day 3
  @cleanup_interval_ms 3_600_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def request_password_reset(email_or_username, ip_address) do
    GenServer.call(__MODULE__, {:request_reset, email_or_username, ip_address})
  end

  def validate_reset_token(token) do
    GenServer.call(__MODULE__, {:validate_token, token})
  end

  def reset_password(token, new_password, ip_address) do
    GenServer.call(__MODULE__, {:reset_password, token, new_password, ip_address})
  end

  def revoke_reset_token(token) do
    GenServer.cast(__MODULE__, {:revoke_token, token})
  end

  def get_reset_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()

    state = %{
      reset_tokens: %{},
      daily_attempts: %{},
      revoked_tokens: MapSet.new()
    }

    Logger.info("Password Reset system started")
    {:ok, state}
  end

  @impl true
  def handle_call({:request_reset, email_or_username, ip_address}, _from, state) do
    case validate_reset_request(email_or_username, ip_address, state) do
      {:ok, user} ->
        token = generate_reset_token()
        expires_at = DateTime.add(DateTime.utc_now(), @reset_token_ttl_hours, :hour)

        reset_data = %{
          user_id: user.id,
          email: user.email || "#{user.username}@jurunense.com",
          username: user.username,
          expires_at: expires_at,
          created_at: DateTime.utc_now(),
          ip_address: ip_address
        }

        new_tokens = Map.put(state.reset_tokens, token, reset_data)
        new_attempts = increment_daily_attempts(state.daily_attempts, user.email || user.username)

        send_reset_email(user, token, reset_data.email)

        SecurityLogger.log_event(:password_reset_requested, user, %{
          ip_address: ip_address,
          email: reset_data.email
        })

        new_state = %{state | reset_tokens: new_tokens, daily_attempts: new_attempts}
        {:reply, {:ok, :reset_email_sent}, new_state}

      {:error, reason} ->
        Logger.warning("Password reset request failed", %{
          email_or_username: email_or_username,
          ip_address: ip_address,
          reason: reason
        })
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:validate_token, token}, _from, state) do
    case Map.get(state.reset_tokens, token) do
      nil ->
        {:reply, {:error, :invalid_token}, state}

      reset_data ->
        if MapSet.member?(state.revoked_tokens, token) do
          {:reply, {:error, :token_revoked}, state}
        else
          now = DateTime.utc_now()
          if DateTime.compare(now, reset_data.expires_at) == :gt do
            new_tokens = Map.delete(state.reset_tokens, token)
            new_state = %{state | reset_tokens: new_tokens}
            {:reply, {:error, :token_expired}, new_state}
          else
            {:reply, {:ok, reset_data}, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:reset_password, token, new_password, ip_address}, _from, state) do
    case validate_reset_token(token, state) do
      {:ok, reset_data} ->
        case Accounts.get_user!(reset_data.user_id) do
          nil ->
            {:reply, {:error, :user_not_found}, state}

          user ->
            case Accounts.update_user(user, %{password: new_password}) do
              {:ok, updated_user} ->
                new_tokens = Map.delete(state.reset_tokens, token)
                new_revoked = MapSet.put(state.revoked_tokens, token)

                SecurityLogger.log_event(:password_reset_completed, updated_user, %{
                  ip_address: ip_address,
                  email: reset_data.email
                })

                send_password_changed_email(updated_user, reset_data.email)

                new_state = %{
                  state |
                  reset_tokens: new_tokens,
                  revoked_tokens: new_revoked
                }

                {:reply, {:ok, :password_reset_successful}, new_state}

              {:error, changeset} ->
                SecurityLogger.log_event(:password_reset_failed, user, %{
                  ip_address: ip_address,
                  reason: :password_update_failed,
                  errors: changeset.errors
                })
                {:reply, {:error, :password_update_failed}, state}
            end
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    now = DateTime.utc_now()

    active_tokens =
      state.reset_tokens
      |> Enum.count(fn {_token, data} ->
        DateTime.compare(now, data.expires_at) == :lt
      end)

    today = Date.utc_today()
    today_attempts =
      state.daily_attempts
      |> Enum.count(fn {_email, {_count, date}} ->
        Date.compare(date, today) == :eq
      end)

    stats = %{
      active_reset_tokens: active_tokens,
      total_reset_tokens: map_size(state.reset_tokens),
      revoked_tokens: MapSet.size(state.revoked_tokens),
      today_reset_attempts: today_attempts,
      total_daily_attempts: map_size(state.daily_attempts)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:revoke_token, token}, state) do
    new_revoked = MapSet.put(state.revoked_tokens, token)
    new_state = %{state | revoked_tokens: new_revoked}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()
    today = Date.utc_today()

    new_tokens =
      state.reset_tokens
      |> Enum.filter(fn {_token, data} ->
        DateTime.compare(now, data.expires_at) == :lt
      end)
      |> Enum.into(%{})

    yesterday = Date.add(today, -1)
    new_attempts =
      state.daily_attempts
      |> Enum.filter(fn {_email, {_count, date}} ->
        Date.compare(date, yesterday) != :lt
      end)
      |> Enum.into(%{})

    new_revoked =
      if MapSet.size(state.revoked_tokens) > 1000 do
        MapSet.new()
      else
        state.revoked_tokens
      end

    cleaned_items = (
      (map_size(state.reset_tokens) - map_size(new_tokens)) +
      (map_size(state.daily_attempts) - map_size(new_attempts)) +
      (MapSet.size(state.revoked_tokens) - MapSet.size(new_revoked))
    )

    if cleaned_items > 0 do
      Logger.debug("Password Reset cleanup: removed #{cleaned_items} expired entries")
    end

    schedule_cleanup()

    new_state = %{
      state |
      reset_tokens: new_tokens,
      daily_attempts: new_attempts,
      revoked_tokens: new_revoked
    }

    {:noreply, new_state}
  end

  defp validate_reset_request(email_or_username, ip_address, state) do
    with user when not is_nil(user) <- find_user_by_email_or_username(email_or_username),
         :ok <- check_daily_limit(user, state),
         :ok <- check_rate_limit(ip_address) do
      {:ok, user}
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_user_by_email_or_username(email_or_username) do
    # Try to find by email first, then by username
    case String.contains?(email_or_username, "@") do
      true -> Accounts.get_user_by_email(email_or_username)
      false -> Accounts.get_user_by_username(email_or_username)
    end
  end

  defp check_daily_limit(user, state) do
    email = user.email || user.username
    today = Date.utc_today()

    case Map.get(state.daily_attempts, email) do
      {count, ^today} when count >= @max_reset_attempts_per_day ->
        {:error, :daily_limit_exceeded}
      _ ->
        :ok
    end
  end

  defp check_rate_limit(ip_address) do
    # Use the existing rate limiter for additional protection
    case App.Auth.RateLimiter.check_login_attempt("password_reset", ip_address) do
      :allowed -> :ok
      {:rate_limited, _} -> {:error, :rate_limited}
      :captcha_required -> :ok  # Allow but could require captcha
    end
  end

  defp generate_reset_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp increment_daily_attempts(attempts_map, email) do
    today = Date.utc_today()

    case Map.get(attempts_map, email) do
      {count, ^today} ->
        Map.put(attempts_map, email, {count + 1, today})
      _ ->
        Map.put(attempts_map, email, {1, today})
    end
  end

  defp validate_reset_token(token, state) do
    case Map.get(state.reset_tokens, token) do
      nil ->
        {:error, :invalid_token}

      reset_data ->
        if MapSet.member?(state.revoked_tokens, token) do
          {:error, :token_revoked}
        else
          now = DateTime.utc_now()
          if DateTime.compare(now, reset_data.expires_at) == :gt do
            {:error, :token_expired}
          else
            {:ok, reset_data}
          end
        end
    end
  end

  defp send_reset_email(user, token, email) do
    reset_url = "#{AppWeb.Endpoint.url()}/reset-password?token=#{token}"

    Email.password_reset_email(user, email, reset_url, token)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Password reset email sent", %{
          user_id: user.id,
          email: email
        })
      {:error, reason} ->
        Logger.error("Failed to send password reset email", %{
          user_id: user.id,
          email: email,
          reason: reason
        })
    end
  end

  defp send_password_changed_email(user, email) do
    Email.password_changed_email(user, email)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Password changed confirmation email sent", %{
          user_id: user.id,
          email: email
        })
      {:error, reason} ->
        Logger.error("Failed to send password changed email", %{
          user_id: user.id,
          email: email,
          reason: reason
        })
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
