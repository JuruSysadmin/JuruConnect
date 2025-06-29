defmodule App.Schemas.LoginAttempt do
  @moduledoc """
  Schema para controlar tentativas de login no rate limiter.

  Armazena tentativas de login por IP e username para implementar
  rate limiting persistente no PostgreSQL.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "login_attempts" do
    field :identifier, :string
    field :identifier_type, :string
    field :attempt_count, :integer, default: 1
    field :first_attempt_at, :utc_datetime_usec
    field :last_attempt_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps()
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(login_attempt, attrs) do
    login_attempt
    |> cast(attrs, [
      :identifier, :identifier_type, :attempt_count,
      :first_attempt_at, :last_attempt_at, :expires_at
    ])
    |> validate_required([
      :identifier, :identifier_type, :attempt_count,
      :first_attempt_at, :last_attempt_at, :expires_at
    ])
    |> validate_inclusion(:identifier_type, ["ip", "username"])
    |> validate_number(:attempt_count, greater_than: 0)
    |> unique_constraint([:identifier, :identifier_type])
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    now = DateTime.utc_now()

    attrs_with_timestamps = attrs
    |> Map.put_new(:first_attempt_at, now)
    |> Map.put_new(:last_attempt_at, now)

    %__MODULE__{}
    |> changeset(attrs_with_timestamps)
  end
end
