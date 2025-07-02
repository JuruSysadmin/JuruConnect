defmodule App.Schemas.SecurityEvent do
  @moduledoc """
  Schema para eventos de segurança do sistema.

  Registra todas as atividades relacionadas à autenticação, autorização
  e operações sensíveis para auditoria e detecção de anomalias.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types [
    "login_success",
    "login_failed",
    "logout",
    "token_refresh",
    "token_refresh_failed",
    "password_changed",
    "password_change_failed",
    "password_reset_requested",
    "password_reset_completed",
    "password_reset_failed",
    "account_locked",
    "suspicious_activity",
    "brute_force_detected",
    "unauthorized_access",
    "privilege_escalation"
  ]

  @severities ["info", "warning", "error", "critical"]

  schema "security_events" do
    field :event_type, :string
    field :username, :string
    field :session_id, :string
    field :ip_address, :string
    field :user_agent, :string
    field :success, :boolean, default: false
    field :failure_reason, :string
    field :metadata, :map
    field :severity, :string
    field :timestamp, :utc_datetime_usec

    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(security_event, attrs) do
    security_event
    |> cast(attrs, [
      :event_type, :user_id, :username, :session_id, :ip_address,
      :user_agent, :success, :failure_reason, :metadata, :severity, :timestamp
    ])
    |> validate_required([:event_type, :timestamp])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_length(:username, max: 255)
    |> validate_length(:failure_reason, max: 500)
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    attrs_with_timestamp = Map.put_new(attrs, :timestamp, DateTime.utc_now())

    %__MODULE__{}
    |> changeset(attrs_with_timestamp)
  end

  @spec event_types() :: [String.t()]
  def event_types, do: @event_types

  @spec severities() :: [String.t()]
  def severities, do: @severities
end
