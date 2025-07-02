defmodule AppWeb.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT authentication.

  Handles token generation, validation, and user resource management
  for secure authentication across the application.
  """

  use Guardian, otp_app: :app

  alias App.Accounts

  def subject_for_token(user, _claims) do
    {:ok, to_string(user.id)}
  end

  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user!(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  rescue
    Ecto.NoResultsError -> {:error, :resource_not_found}
  end

  def claims(claims, _resource, _opts) do
    claims =
      claims
      |> Map.put("typ", "access")
      |> Map.put("aud", "app_web")

    {:ok, claims}
  end

  def verify_claims(claims, _options) do
    aud = Map.get(claims, "aud")
    typ = Map.get(claims, "typ")

    cond do
      is_nil(aud) -> {:error, :invalid_audience}
      aud != "app_web" -> {:error, :invalid_audience}
      is_nil(typ) -> {:error, :invalid_token_type}
      typ not in ["access", "refresh"] -> {:error, :invalid_token_type}
      true -> {:ok, claims}
    end
  end

  def after_encode_and_sign(resource, claims, token, _options) do
    with {:ok, _} <- Guardian.DB.after_encode_and_sign(resource, claims["typ"], claims, token) do
      {:ok, token}
    end
  end

  def on_verify(claims, token, _options) do
    case Guardian.DB.on_verify(claims, token) do
      {:ok, _} -> {:ok, claims}
      {:error, :token_not_found} -> {:error, :token_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _options) do
    with {:ok, _, _} <- Guardian.DB.on_refresh({old_token, old_claims}, {new_token, new_claims}) do
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    end
  end

  def on_revoke(claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end
end
