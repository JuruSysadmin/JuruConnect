# Script de coleta da API real
# Execute: mix run cole_dados.exs

defmodule ColetaDados do
  @moduledoc """
  Script para coleta manual de dados da API de supervisores.

  Este módulo realiza uma única coleta de dados da API interna,
  processa e salva no banco de dados PostgreSQL.

  Funcionalidades:
  - Conexão com API interna
  - Validação e normalização dos dados
  - Persistência no banco de dados
  - Exibição de estatísticas coletadas
  - Ranking dos melhores vendedores

  Execute com: mix run cole_dados.exs
  """

  alias JuruConnect.Api.SupervisorClient

  @api_url "http://10.1.1.108:8065/api/v1/dashboard/sale/12"

  def run do
    IO.puts("Coletando dados da API interna...")
    collect_and_save_data()
    show_usage_info()
  end

  defp collect_and_save_data do
    case SupervisorClient.fetch_and_save(@api_url) do
      {:ok, data} ->
        display_success_info(data)
        display_top_sellers(data)

      {:error, reason} ->
        display_error_info(reason)
    end
  end

  defp display_success_info(data) do
    IO.puts("SUCESSO! Dados coletados e salvos")
    IO.puts("   ID: #{data.id}")
    IO.puts("   Performance: #{data.percentual_sale}%")
    IO.puts("   Vendas: R$ #{data.sale}")
    IO.puts("   Meta: R$ #{data.objective}")
    IO.puts("   Vendedores: #{length(data.sale_supervisor)}")
    IO.puts("   Coletado em: #{data.collected_at}")
  end

  defp display_top_sellers(data) do
    if length(data.sale_supervisor) > 0 do
      IO.puts("\nTop 3 Vendedores:")

      data.sale_supervisor
      |> Enum.sort_by(& &1["percentualObjective"], :desc)
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.each(fn {seller, pos} ->
        name = seller["sellerName"] || "Nome não informado"
        performance = seller["percentualObjective"] || 0
        sales = seller["saleValue"] || 0

        IO.puts("   #{pos}. #{name}")
        IO.puts("      Performance: #{performance}%")
        IO.puts("      Vendas: R$ #{sales}")
      end)
    end
  end

  defp display_error_info(reason) do
    IO.puts("ERRO ao coletar dados:")

    case reason do
      {:http_request_error, :nxdomain} ->
        IO.puts("   Servidor não encontrado")
        IO.puts("   Verifique se o IP 10.1.1.108 está acessível")

      {:http_request_error, :econnrefused} ->
        IO.puts("   Conexão recusada")
        IO.puts("   Verifique se o serviço está rodando na porta 8065")

      {:http_error, status, _body} ->
        IO.puts("   HTTP #{status}")
        IO.puts("   Verifique se a URL está correta")

      other ->
        IO.puts("   #{inspect(other)}")
    end

    display_troubleshooting_info()
  end

  defp display_troubleshooting_info do
    IO.puts("\nPara debugar:")
    IO.puts("   1. Teste no navegador: #{@api_url}")
    IO.puts("   2. Teste no terminal: curl #{@api_url}")
    IO.puts("   3. Verifique conectividade: ping 10.1.1.108")
  end

  defp show_usage_info do
    IO.puts("\nPara ver dados salvos:")
    IO.puts("   iex -S mix")
    IO.puts("   JuruConnect.Sales.get_latest_supervisor_data()")
  end
end

ColetaDados.run()
