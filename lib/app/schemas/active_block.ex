defmodule App.Schemas.ActiveBlock do
  @moduledoc """
  Schema para controlar bloqueios ativos no rate limiter.

  Armazena bloqueios temporários de IPs e usuários que excederam
  os limites de tentativas de login.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @block_reasons [
    "excessive_login_attempts",
    "brute_force_detected",
    "suspicious_activity",
    "manual_block",
    "security_policy_violation"
  ]

  schema "active_blocks" do
    field :identifier, :string
    field :identifier_type, :string
    field :reason, :string
    field :blocked_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :metadata, :map

    timestamps()
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(active_block, attrs) do
    active_block
    |> cast(attrs, [
      :identifier, :identifier_type, :reason,
      :blocked_at, :expires_at, :metadata
    ])
    |> validate_required([
      :identifier, :identifier_type, :reason,
      :blocked_at, :expires_at
    ])
    |> validate_inclusion(:identifier_type, ["ip", "username"])
    |> validate_inclusion(:reason, @block_reasons)
    |> unique_constraint([:identifier, :identifier_type])
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    attrs_with_timestamp = Map.put_new(attrs, :blocked_at, DateTime.utc_now())

    %__MODULE__{}
    |> changeset(attrs_with_timestamp)
  end

  @spec block_reasons() :: [String.t()]
  def block_reasons, do: @block_reasons
end
