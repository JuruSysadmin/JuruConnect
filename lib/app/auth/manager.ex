defmodule App.Auth.Manager do
  @moduledoc """
  Central authentication manager that unifies all auth operations.

  This module provides a single interface for all authentication-related
  operations including login, logout, session management, and security
  features like rate limiting and comprehensive audit logging.

  ## Features

  - **Secure Authentication**: Username/password validation with bcrypt
  - **JWT Token Management**: Access and refresh tokens via Guardian
  - **Rate Limiting**: Prevents brute force attacks with configurable limits
  - **Security Logging**: Comprehensive audit trail for all auth events
  - **Session Management**: Token refresh and revocation
  - **Password Management**: Secure password change with validation

  ## Usage

      # Authenticate user
      auth_params = %{
        username: "admin",
        password: "password123",
        ip_address: "192.168.1.100"
      }

      case App.Auth.Manager.authenticate(auth_params) do
        {:ok, %{user: user, access_token: token}} ->
          # Login successful
        {:error, :invalid_credentials} ->
          # Invalid username/password
        {:error, {:rate_limited, retry_after}} ->
          # Too many attempts, try again in retry_after seconds
      end

      # Refresh session
      case App.Auth.Manager.refresh_session(refresh_token, ip_address) do
        {:ok, %{access_token: new_token}} ->
          # New token generated
        {:error, :invalid_refresh_token} ->
          # Refresh token expired or invalid
      end

  ## Security Features

  - **Rate Limiting**: 5 attempts per minute per IP/username combination
  - **Audit Logging**: All authentication events are logged with timestamps
  - **Token Expiration**: Access tokens expire in 1 hour, refresh in 7 days
  - **IP Tracking**: All operations track originating IP addresses
  - **Brute Force Protection**: Automatic blocking after repeated failures

  ## Configuration

  Configure rate limiting and token expiration in your config:

      config :app, App.Auth.RateLimiter,
        max_attempts: 5,
        window_seconds: 60

      config :app, AppWeb.Auth.Guardian,
        ttl: {1, :hour},
        refresh_ttl: {7, :day}

  """

  require Logger

  alias App.Accounts
  alias App.Auth.RateLimiter
  alias App.Auth.SecurityLogger
  alias AppWeb.Auth.Guardian

  @typedoc "Authentication result with user and tokens or error"
  @type auth_result :: {:ok, map()} | {:error, atom() | String.t()}

  @typedoc "Login parameters required for authentication"
  @type login_params :: %{username: String.t(), password: String.t(), ip_address: String.t()}

  @doc """
  Authenticates a user with comprehensive security checks.

  This function performs the complete authentication flow including parameter
  validation, rate limiting, credential verification, token generation, and
  security logging.

  ## Parameters

  - `params` - Map containing:
    - `:username` - User's username (string, required)
    - `:password` - User's password (string, required)
    - `:ip_address` - Client's IP address (string, required)

  ## Returns

  - `{:ok, %{user: user, access_token: token, refresh_token: refresh_token}}` - Success
  - `{:error, :invalid_credentials}` - Invalid username/password
  - `{:error, {:rate_limited, retry_after}}` - Too many attempts
  - `{:error, :token_generation_failed}` - Failed to generate tokens

  ## Examples

      # Successful login
      params = %{
        username: "john_doe",
        password: "secure_password123",
        ip_address: "192.168.1.100"
      }

      {:ok, %{user: user, access_token: token}} =
        App.Auth.Manager.authenticate(params)

      # Rate limited
      {:error, {:rate_limited, 45}} =
        App.Auth.Manager.authenticate(params)

  """
  @spec authenticate(login_params()) :: auth_result()
  def authenticate(params) do
    params
    |> validate_login_params()
    |> check_rate_limits()
    |> attempt_authentication()
    |> generate_tokens()
    |> log_auth_event()
  end

  @doc """
  Refreshes an authentication session using a refresh token.

  Validates the refresh token and generates a new access token while keeping
  the same refresh token (unless it's close to expiration).

  ## Parameters

  - `refresh_token` - Valid JWT refresh token (string)
  - `ip_address` - Client's IP address for logging (string)

  ## Returns

  - `{:ok, %{user: user, access_token: new_token, refresh_token: refresh_token}}` - Success
  - `{:error, :invalid_refresh_token}` - Invalid or expired refresh token

  ## Examples

      {:ok, %{access_token: new_token}} =
        App.Auth.Manager.refresh_session(refresh_token, "192.168.1.100")

  """
  @spec refresh_session(String.t(), String.t()) :: auth_result()
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

  @doc """
  Logs out a user by revoking their access token.

  This function validates the token, revokes it to prevent further use,
  and logs the logout event for security audit purposes.

  ## Parameters

  - `token` - Valid JWT access token (string)
  - `ip_address` - Client's IP address for logging (string)

  ## Returns

  - `{:ok, :logged_out}` - Successfully logged out
  - `{:error, :logout_failed}` - Failed to logout (invalid token)

  ## Examples

      {:ok, :logged_out} =
        App.Auth.Manager.logout(access_token, "192.168.1.100")

  """
  @spec logout(String.t(), String.t()) :: {:ok, :logged_out} | {:error, :logout_failed}
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

  @doc """
  Validates a session token and returns the associated user.

  This is used to verify if a user's session is still valid and to retrieve
  user information from a token.

  ## Parameters

  - `token` - JWT access token to validate (string)

  ## Returns

  - `{:ok, user}` - Token is valid, returns user struct
  - `{:error, reason}` - Token is invalid or expired

  ## Examples

      case App.Auth.Manager.validate_session(token) do
        {:ok, user} ->
          # User is authenticated
        {:error, :token_expired} ->
          # Redirect to login
      end

  """
  @spec validate_session(String.t()) :: {:ok, Accounts.User.t()} | {:error, any()}
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

  @doc """
  Changes a user's password with current password verification.

  This function verifies the current password before allowing the change,
  ensuring security and logging all password change attempts.

  ## Parameters

  - `user` - User struct whose password is being changed
  - `current_password` - User's current password for verification
  - `new_password` - New password to set
  - `ip_address` - Client's IP address for logging

  ## Returns

  - `{:ok, updated_user}` - Password changed successfully
  - `{:error, :invalid_current_password}` - Current password is wrong
  - `{:error, :password_change_failed}` - General failure

  ## Examples

      case App.Auth.Manager.change_password(user, "old_pass", "new_pass", ip) do
        {:ok, updated_user} ->
          # Password changed successfully
        {:error, :invalid_current_password} ->
          # Wrong current password
      end

  """
  @spec change_password(Accounts.User.t(), String.t(), String.t(), String.t()) ::
    {:ok, Accounts.User.t()} | {:error, atom()}
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

  defp log_auth_event({:ok, %{user: user, ip_address: ip_address, auth_result: result} = _params}) do
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
