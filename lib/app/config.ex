defmodule App.Config do
  @moduledoc """
  Configurações centralizadas da aplicação.

  Centraliza todas as configurações de limites, URLs e parâmetros
  para facilitar manutenção e ajustes.
  """

    @doc """
  Limite padrão para busca do feed de vendas.

  Configurado para incluir todos os parceiros conhecidos.
  """
  def sales_feed_limit, do: 50

  @doc """
  Limite máximo permitido para busca do feed de vendas.
  """
  def sales_feed_max_limit, do: 100

  @doc """
  URLs das APIs externas.
  """
  def api_urls do
    %{
      sales_feed: "http://vendaweb.jurunense.com.br/api/v1/dashboard/sale",
      dashboard_base: "http://10.1.1.212:8065/api/v1",
      dashboard_sale: "http://10.1.1.212:8065/api/v1/dashboard/sale",
      dashboard_companies: "http://10.1.1.212:8065/api/v1/dashboard/sale/company"
    }
  end

  @doc """
  Configurações do leaderboard.
  """
  def leaderboard_config do
    %{
      default_limit: sales_feed_limit(),
      update_interval_seconds: 30,
      max_displayed_sellers: 100
    }
  end
end
