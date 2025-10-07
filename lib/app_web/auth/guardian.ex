defmodule AppWeb.Auth.Guardian do
  @moduledoc """
  Guardian authentication module.
  """

  use Guardian, otp_app: :app


  def subject_for_token(%{id: id}, _claims) do
    sub = to_string(id)
    {:ok, sub}
  end

  def subject_for_token(_, _) do
    {:error, :reason_for_error}
  end

    def resource_from_claims(%{"sub" => id}) do
    # Converter string para UUID se necessário
    user_id = case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> id
    end

        case App.Repo.get(App.Accounts.User, user_id) do
      nil ->
        {:error, :resource_not_found}
      user ->
        {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end
end
