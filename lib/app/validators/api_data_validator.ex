defmodule App.Validators.ApiDataValidator do
  @moduledoc """
  Validador para dados vindos da API externa.
  Garante integridade e segurança dos dados antes do processamento.
  """


  def validate_dashboard_data(data) when is_map(data) do
    validate_companies_key(data)
  end

  def validate_dashboard_data(_), do: {:error, "Invalid dashboard data format"}

  defp validate_companies_key(data) do
    case Map.has_key?(data, "companies") or Map.has_key?(data, :companies) do
      true -> {:ok, data}
      false -> {:error, "Invalid dashboard data structure"}
    end
  end
end
