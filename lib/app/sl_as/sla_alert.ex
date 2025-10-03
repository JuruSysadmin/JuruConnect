defmodule App.SLAs.SLAAlert do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sla_alerts" do
    field :category, :string
    field :priority, :string
    field :sla_hours, :integer
    field :warning_hours, :integer
    field :critical_hours, :integer
    field :status, :string, default: "active"
    field :alerted_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :alert_type, :string # "warning", "critical", "breach"
    field :escalated_at, :utc_datetime
    field :escalated_to, :string

    # Relacionamentos
    belongs_to :treaty, App.Treaties.Treaty, foreign_key: :treaty_id
    belongs_to :created_by_user, App.Accounts.User, foreign_key: :created_by

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a SLA alert.
  """
  def changeset(sla_alert, attrs) do
    sla_alert
    |> cast(attrs, [:treaty_id, :category, :priority, :sla_hours, :warning_hours, :critical_hours, :status, :alerted_at, :resolved_at, :created_by, :alert_type, :escalated_at, :escalated_to])
    |> validate_required([:treaty_id, :category, :priority, :sla_hours, :warning_hours, :critical_hours])
    |> validate_inclusion(:status, ["active", "resolved", "cancelled"])
    |> validate_inclusion(:priority, ["low", "normal", "high", "urgent"])
    |> validate_inclusion(:category, ["FINANCEIRO", "COMERCIAL", "LOGISTICA"])
    |> validate_inclusion(:alert_type, ["warning", "critical", "breach"])
    |> validate_number(:sla_hours, greater_than: 0)
    |> validate_number(:warning_hours, greater_than: 0)
    |> validate_number(:critical_hours, greater_than: 0)
    |> foreign_key_constraint(:treaty_id)
    |> foreign_key_constraint(:created_by)
  end

  @doc """
  Creates a changeset for creating a new SLA alert.
  """
  def create_changeset(sla_alert, attrs) do
    sla_alert
    |> changeset(attrs)
    |> put_change(:status, "active")
    |> put_change(:alerted_at, DateTime.utc_now())
  end
end
