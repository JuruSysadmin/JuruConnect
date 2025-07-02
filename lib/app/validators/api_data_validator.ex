defmodule App.Validators.ApiDataValidator do
  @moduledoc """
  Validador para dados vindos da API externa.
  Garante integridade e segurança dos dados antes do processamento.
  """

  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :seller_name, :string
    field :store, :string
    field :sale_value, :decimal
    field :objetivo, :decimal
    field :timestamp, :utc_datetime
    field :type, :string
  end

  def validate_sale_data(data) when is_map(data) do
    %__MODULE__{}
    |> cast(data, [:seller_name, :store, :sale_value, :objetivo, :timestamp, :type])
    |> validate_required([:seller_name, :store, :sale_value, :timestamp])
    |> validate_length(:seller_name, min: 1, max: 255)
    |> validate_length(:store, min: 1, max: 100)
    |> validate_number(:sale_value, greater_than: 0, less_than: 1_000_000)
    |> validate_number(:objetivo, greater_than_or_equal_to: 0)
    |> validate_inclusion(:type, ["sale_supervisor", "api", "manual"])
    |> validate_datetime_not_future(:timestamp)
  end

  def validate_sale_data(_), do: {:error, "Invalid data format"}

  defp validate_datetime_not_future(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if DateTime.compare(value, DateTime.utc_now()) == :gt do
        [{field, "cannot be in the future"}]
      else
        []
      end
    end)
  end

  def sanitize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[<>\"'&]/, "")
    |> String.slice(0, 255)
  end

  def sanitize_string(value), do: value

  def validate_dashboard_data(data) when is_map(data) do
    if Map.has_key?(data, "companies") or Map.has_key?(data, :companies) do
      {:ok, data}
    else
      {:error, "Invalid dashboard data structure"}
    end
  end

  def validate_dashboard_data(_), do: {:error, "Invalid dashboard data format"}
end
