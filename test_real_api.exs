# Teste com API real
# Execute: mix run test_real_api.exs

defmodule TestRealApi do
  @moduledoc """
  Script de teste para validar integração com API real de supervisores.

  Este módulo executa uma bateria de testes para verificar:
  - Conectividade com a API
  - Parsing dos dados recebidos
  - Persistência no banco de dados
  - Consultas aos dados salvos
  - Ranking de vendedores

  Execute com: mix run test_real_api.exs
  """

  alias JuruConnect.{Api.SupervisorClient, Sales}

  @api_url "http://10.1.1.108:8065/api/v1/dashboard/sale/12"

  def run do
    IO.puts("Testando integração com API real: #{@api_url}")
    test_api_connection()
    show_next_steps()
  end

  defp test_api_connection do
    IO.puts("\nTeste 1: Verificando conectividade com API...")

    case SupervisorClient.fetch_data(@api_url) do
      {:ok, data} ->
        IO.puts("Dados recebidos da API com sucesso")
        IO.puts("   Objetivo: #{data["objetive"] || "N/A"}")
        IO.puts("   Vendas: #{data["sale"] || "N/A"}")
        IO.puts("   Percentual: #{data["percentualSale"] || "N/A"}%")
        IO.puts("   Vendedores: #{length(data["saleSupervisor"] || [])}")

        test_data_persistence(data)

      {:error, reason} ->
        handle_api_error(reason)
    end
  end

  defp test_data_persistence(data) do
    IO.puts("\nTeste 2: Persistindo dados no banco...")

    case Sales.create_supervisor_data_from_api(data) do
      {:ok, supervisor_data} ->
        IO.puts("Dados salvos no banco com sucesso")
        IO.puts("   ID: #{supervisor_data.id}")
        IO.puts("   Coletado em: #{supervisor_data.collected_at}")
        IO.puts("   Vendedores salvos: #{length(supervisor_data.sale_supervisor)}")

        test_data_queries()
        test_top_performers(supervisor_data)

      {:error, changeset} ->
        IO.puts("Erro ao salvar dados no banco:")
        IO.inspect(changeset.errors)
    end
  end

  defp test_data_queries do
    IO.puts("\nTeste 3: Consultando dados salvos...")

    case Sales.get_latest_supervisor_data() do
      nil ->
        IO.puts("Nenhum dado encontrado")
      latest ->
        IO.puts("   Performance atual: #{latest.percentual_sale}%")
        IO.puts("   Vendas: R$ #{latest.sale}")
    end
  end

  defp test_top_performers(supervisor_data) do
    if length(supervisor_data.sale_supervisor) > 0 do
      IO.puts("\nTeste 4: Top 3 vendedores por performance:")

      supervisor_data.sale_supervisor
      |> Enum.sort_by(& &1["percentualObjective"], :desc)
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.each(fn {seller, pos} ->
        IO.puts("   #{pos}. #{seller["sellerName"]}")
        IO.puts("      Performance: #{seller["percentualObjective"]}%")
        IO.puts("      Vendas: R$ #{seller["saleValue"]}")
      end)
    end
  end

  defp handle_api_error(reason) do
    IO.puts("Erro ao conectar com a API:")
    IO.inspect(reason)

    IO.puts("\nPossíveis soluções:")
    IO.puts("   1. Verifique se a API está rodando")
    IO.puts("   2. Teste no navegador: #{@api_url}")
    IO.puts("   3. Verifique conectividade de rede")
    IO.puts("   4. Confirme se não precisa de autenticação")
  end

  defp show_next_steps do
    IO.puts("\nPróximos passos:")
    IO.puts("Para configurar sincronização automática:")
    IO.puts("   SupervisorClient.start_periodic_sync(\"#{@api_url}\", 3600)")
    IO.puts("   Coleta a cada 1 hora (3600 segundos)")

    IO.puts("\nPara acompanhar dados:")
    IO.puts("   Sales.get_latest_supervisor_data()")
    IO.puts("   Sales.list_supervisor_data(limit: 10)")
  end
end

TestRealApi.run()
