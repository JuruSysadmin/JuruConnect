defmodule AppWeb.Auth.Guardian do
  use Guardian, otp_app: :app

  alias App.Accounts

  def subject_for_token(%{id: id}, _claims) do
    sub = to_string(id)
    {:ok, sub}
  end

  def subject_for_token(_, _) do
    {:error, :reason_for_error}
  end

    def resource_from_claims(%{"sub" => id}) do
    require Logger
    Logger.info("Guardian: Tentando buscar usuário com ID = #{id}")

    # Converter string para UUID se necessário
    user_id = case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> id
    end

        case App.Repo.get(App.Accounts.User, user_id) do
      nil ->
        Logger.error("Guardian: Usuário não encontrado com ID = #{user_id}")
        {:error, :resource_not_found}
      user ->
        Logger.info("Guardian: Usuário encontrado = #{user.name || user.username}")
        {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end
end
