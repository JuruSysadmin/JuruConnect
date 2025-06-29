defmodule App.Auth.Manager do
  @moduledoc """
  Central authentication manager that unifies all auth operations.

  Provides a single interface for login, logout, session management,
  and security features like rate limiting and audit logging.
  """

  require Logger

  alias App.Accounts
  alias App.Auth.RateLimiter
  alias App.Auth.SecurityLogger
  alias AppWeb.Auth.Guardian

  @type auth_result :: {:ok, map()} | {:error, atom() | String.t()}
  @type login_params :: %{username: String.t(), password: String.t(), ip_address: String.t()}

  def authenticate(params) do
    params
    |> validate_login_params()
    |> check_rate_limits()
    |> attempt_authentication()
    |> generate_tokens()
    |> log_auth_event()
  end

  def refresh_session(refresh_token, ip_address) do
    with {:ok, claims} <- Guardian.decode_and_verify(refresh_token),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         {:ok, new_token, _claims} <- Guardian.encode_and_sign(user) do

      SecurityLogger.log_event(:token_refresh, user, %{ip_address: ip_address})

      {:ok, %{
        user: user,
        access_token: new_token,
        refresh_token: refresh_token
      }}
    else
      error ->
        SecurityLogger.log_event(:token_refresh_failed, nil, %{
          ip_address: ip_address,
          error: error
        })
        {:error, :invalid_refresh_token}
    end
  end

  def logout(token, ip_address) do
    with {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         {:ok, _claims} <- Guardian.revoke(token) do

      SecurityLogger.log_event(:logout, user, %{ip_address: ip_address})
      {:ok, :logged_out}
    else
      error ->
        SecurityLogger.log_event(:logout_failed, nil, %{
          ip_address: ip_address,
          error: error
        })
        {:error, :logout_failed}
    end
  end

  def validate_session(token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} -> {:ok, user}
          error -> error
        end
      error -> error
    end
  end

  def change_password(user, current_password, new_password, ip_address) do
    with {:ok, verified_user} <- Accounts.authenticate_user(user.username, current_password),
         {:ok, updated_user} <- Accounts.update_user(verified_user, %{password: new_password}) do

      SecurityLogger.log_event(:password_changed, updated_user, %{ip_address: ip_address})
      {:ok, updated_user}
    else
      {:error, :unauthorized} ->
        SecurityLogger.log_event(:password_change_failed, user, %{
          ip_address: ip_address,
          reason: :invalid_current_password
        })
        {:error, :invalid_current_password}

      error ->
        SecurityLogger.log_event(:password_change_failed, user, %{
          ip_address: ip_address,
          error: error
        })
        {:error, :password_change_failed}
    end
  end

  defp validate_login_params(%{username: username, password: password} = params)
    when is_binary(username) and is_binary(password) and
         byte_size(username) > 0 and byte_size(password) > 0 do
    {:ok, params}
  end

  defp validate_login_params(_params) do
    {:error, :invalid_credentials}
  end

  defp check_rate_limits({:ok, %{username: username, ip_address: ip_address} = params}) do
    case RateLimiter.check_login_attempt(username, ip_address) do
      :allowed -> {:ok, params}
      {:rate_limited, retry_after} -> {:error, {:rate_limited, retry_after}}
      :captcha_required -> {:ok, Map.put(params, :captcha_required, true)}
    end
  end

  defp check_rate_limits(error), do: error

  defp attempt_authentication({:ok, %{username: username, password: password} = params}) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} -> {:ok, Map.put(params, :user, user)}
      {:error, :unauthorized} -> {:error, :invalid_credentials}
    end
  end

  defp attempt_authentication(error), do: error

  defp generate_tokens({:ok, %{user: user} = params}) do
    with {:ok, access_token, _access_claims} <- Guardian.encode_and_sign(user, %{}, token_type: "access"),
         {:ok, refresh_token, _refresh_claims} <- Guardian.encode_and_sign(user, %{}, token_type: "refresh") do

      result = %{
        user: user,
        access_token: access_token,
        refresh_token: refresh_token,
        captcha_required: Map.get(params, :captcha_required, false)
      }

      {:ok, Map.put(params, :auth_result, result)}
    else
      {:error, _reason} ->
        {:error, :token_generation_failed}
    end
  end

  defp generate_tokens(error), do: error

  defp log_auth_event({:ok, %{user: user, ip_address: ip_address, auth_result: result} = params}) do
    SecurityLogger.log_event(:login_success, user, %{
      ip_address: ip_address,
      captcha_required: result.captcha_required
    })

    RateLimiter.reset_attempts(user.username, ip_address)
    {:ok, result}
  end

  defp log_auth_event({:error, reason} = error) do
    # Log failed authentication attempt
    Logger.warning("Authentication failed: #{inspect(reason)}")
    error
  end
end
