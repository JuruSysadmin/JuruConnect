defmodule AppWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation module for handling authentication in the AppWeb context.

  This module defines the necessary callbacks for Guardian to encode and decode user tokens,
  retrieve user resources from claims, and handle post-verification logic.

  ## Callbacks

  - `subject_for_token/2`: Encodes the user's ID as the subject in the token.
  - `resource_from_claims/1`: Retrieves the user resource from the token claims.
  - `after_decode_and_verify/3`: Processes the claims and token after decoding and verification.
  - `after_verify/3`: Handles logic after token verification.

  ## Usage

  This module is used by Guardian to manage authentication tokens for users in the application.
  """

  use Guardian, otp_app: :app

  alias App.Accounts.User
  alias App.Repo

  @impl true
  def subject_for_token(%User{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  @impl true
  def resource_from_claims(%{"sub" => id}) do
    case Repo.get(User, id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end
end
