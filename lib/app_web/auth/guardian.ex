defmodule AppWeb.Auth.Guardian do
  @moduledoc """
  Guardian authentication module for JWT token management.

  Handles JWT token creation and validation for user authentication.
  Provides secure token-based authentication with user session management.
  """

  use Guardian, otp_app: :app

  require Logger

  @doc """
  Creates a subject identifier for JWT token from user data.

  Converts user ID to string format for token subject claim.
  """
  def subject_for_token(%{id: user_id}, _claims) do
    subject_id = to_string(user_id)
    {:ok, subject_id}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_user_data}
  end

  @doc """
  Retrieves user resource from JWT token claims.

  Validates token subject and fetches user from database.
  Handles UUID conversion and user lookup with proper error handling.
  """
  def resource_from_claims(%{"sub" => subject_id}) do
    Logger.info("Guardian: Attempting to fetch user with ID = #{subject_id}")

    user_id = normalize_user_id(subject_id)

    case App.Repo.get(App.Accounts.User, user_id) do
      nil ->
        Logger.error("Guardian: User not found with ID = #{user_id}")
        {:error, :resource_not_found}
      user ->
        Logger.info("Guardian: User found = #{user.name || user.username}")
        {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_token_claims}
  end

  # Normalizes user ID format for database lookup
  defp normalize_user_id(subject_id) do
    case Ecto.UUID.cast(subject_id) do
      {:ok, uuid} -> uuid
      :error -> subject_id
    end
  end
end
