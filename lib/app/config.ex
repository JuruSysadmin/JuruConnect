defmodule App.Config do
  @moduledoc """
  Configurações centralizadas da aplicação.

  Centraliza todas as configurações de limites, URLs e parâmetros
  para facilitar manutenção e ajustes.
  """

  def sales_feed_limit, do: 50

  def sales_feed_max_limit, do: 100

  def api_urls do
    %{
      sales_feed: "http://vendaweb.jurunense.com.br/api/v1/dashboard/sale",
      dashboard_base: "http://10.1.1.212:8065/api/v1",
      dashboard_sale: "http://10.1.1.212:8065/api/v1/dashboard/sale",
      dashboard_companies: "http://10.1.1.212:8065/api/v1/dashboard/sale/company"
    }
  end


end
