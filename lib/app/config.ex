defmodule App.Config do
  @moduledoc """
  Configurações centralizadas da aplicação.

  Centraliza todas as configurações de limites, URLs e parâmetros
  para facilitar manutenção e ajustes.
  """

  def api_urls do
    %{
      dashboard_base: "http://10.1.1.212:8065/api/v1",
      dashboard_sale: "http://10.1.1.212:8065/api/v1/dashboard/sale",
      dashboard_companies: "http://10.1.1.212:8065/api/v1/dashboard/sale/company",
      dashboard_seller: "http://10.1.1.108:8065/api/v1/dashboard/sale",
      dashboard_schedule: "http://10.1.1.212:8065/api/v1/shipping/schedule",
      dashboard_returns: "http://10.1.1.168:8065/api/v1/dashboard/returns/by-day"
    }
  end

  def api_timeout_ms do
    Application.get_env(:app, :api_timeout_ms, 10_000)
  end
end
