defmodule App.Validators.ApiDataValidator do
  @moduledoc """
  Validador para dados vindos da API externa.
  Garante integridade e segurança dos dados antes do processamento.
  """


  def validate_dashboard_data(data) when is_map(data) do
    if Map.has_key?(data, "companies") or Map.has_key?(data, :companies) do
      {:ok, data}
    else
      {:error, "Invalid dashboard data structure"}
    end
  end

  def validate_dashboard_data(_), do: {:error, "Invalid dashboard data format"}
end
