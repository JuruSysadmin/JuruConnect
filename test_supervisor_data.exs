defmodule TestSupervisorData do
  @moduledoc """
  Suite de testes completa para o sistema de dados de supervisores.

  Este módulo executa testes abrangentes incluindo:
  - Persistência de dados de exemplo
  - Consultas de dados recentes
  - Análise de performance de vendedores
  - Histórico de vendedores específicos
  - Listagem com filtros

  Execute com: mix run test_supervisor_data.exs
  """

  alias JuruConnect.Sales

  def run do
    IO.puts("Testando sistema de dados de supervisores...")

    test_data_persistence()
    test_recent_data_queries()
    test_top_performers()
    test_seller_history()
    test_data_listing()
    show_next_steps()
  end

  defp sample_data do
    %{
      "objetive" => 8563636.4,
      "sale" => 7521999.753500001,
      "percentualSale" => 87.84,
      "discount" => 1663736.846499999,
      "nfs" => 12324,
      "mix" => 25212,
      "objetiveToday" => 290454.55,
      "saleToday" => 291.46000000000004,
      "nfsToday" => 8,
      "devolution" => 1451707.5464999995,
      "objetiveHour" => 26903.35269375,
      "percentualObjetiveHour" => 1.08,
      "objetiveTotalHour" => 26903.35269375,
      "percentualObjetiveTotalHour" => 1.08,
      "saleSupervisor" => [
        sample_seller_data(1217, "BR - ALVARO DO ESPIRITO SANTO DAS DORES", 327775.8463, 124.87),
        sample_seller_data(354, "BR - ARNALDO GARCIA FERREIRA", 405056.5142, 154.31),
        sample_seller_data(189, "BR - JHONATA ALEF MATOS CAMPOS", 689703.5598, 262.74)
      ]
    }
  end

  defp sample_seller_data(seller_id, name, sale_value, performance) do
    %{
      "supervisorId" => 12,
      "store" => "JURUNENSE BR",
      "sellerId" => seller_id,
      "sellerName" => name,
      "qtdeDaysMonth" => 21,
      "qtdeDays" => 20,
      "objetivo" => 262500,
      "saleValue" => sale_value,
      "percentualObjective" => performance,
      "qtdeInvoice" => 300,
      "ticket" => 900.0,
      "mix" => 500
    }
  end

  defp test_data_persistence do
    IO.puts("\nTeste 1: Salvando dados de exemplo...")

    case Sales.create_supervisor_data_from_api(sample_data()) do
      {:ok, supervisor_data} ->
        IO.puts("Dados salvos com sucesso!")
        IO.puts("   ID: #{supervisor_data.id}")
        IO.puts("   Objetivo: R$ #{supervisor_data.objective}")
        IO.puts("   Vendas: R$ #{supervisor_data.sale}")
        IO.puts("   Percentual: #{supervisor_data.percentual_sale}%")
        IO.puts("   Vendedores: #{length(supervisor_data.sale_supervisor)}")
        IO.puts("   Coletado em: #{supervisor_data.collected_at}")

      {:error, changeset} ->
        IO.puts("Erro ao salvar dados:")
        IO.inspect(changeset.errors)
    end
  end

  defp test_recent_data_queries do
    IO.puts("\nTeste 2: Buscando dados mais recentes...")

    case Sales.get_latest_supervisor_data() do
      nil ->
        IO.puts("Nenhum dado encontrado")
      data ->
        IO.puts("Dados encontrados:")
        IO.puts("   Vendas: R$ #{data.sale}")
        IO.puts("   Meta: R$ #{data.objective}")
        IO.puts("   Atingimento: #{data.percentual_sale}%")
        IO.puts("   Data: #{data.collected_at}")
    end
  end

  defp test_top_performers do
    IO.puts("\nTeste 3: Top 3 vendedores...")

    date_from = DateTime.add(DateTime.utc_now(), -24 * 60 * 60)
    date_to = DateTime.utc_now()

    top_performers = Sales.get_top_performers(3, date_from, date_to)

    if length(top_performers) > 0 do
      IO.puts("Top performers encontrados:")

      top_performers
      |> Enum.with_index(1)
      |> Enum.each(fn {seller, position} ->
        IO.puts("   #{position}. #{seller["sellerName"]}")
        IO.puts("      Performance: #{seller["percentualObjective"]}%")
        IO.puts("      Vendas: R$ #{seller["saleValue"]}")
        IO.puts("      Store: #{seller["store"]}")
        IO.puts("")
      end)
    else
      IO.puts("Nenhum vendedor encontrado no período")
    end
  end

  defp test_seller_history do
    IO.puts("\nTeste 4: Histórico do vendedor 1217...")

    date_from = DateTime.add(DateTime.utc_now(), -24 * 60 * 60)
    date_to = DateTime.utc_now()

    seller_history = Sales.get_seller_history(1217, date_from, date_to)

    if length(seller_history) > 0 do
      IO.puts("Histórico encontrado:")

      Enum.each(seller_history, fn record ->
        if record.seller_data do
          IO.puts("   Data: #{record.collected_at}")
          IO.puts("   Performance: #{record.seller_data["percentualObjective"]}%")
          IO.puts("   Vendas: R$ #{record.seller_data["saleValue"]}")
          IO.puts("")
        end
      end)
    else
      IO.puts("Nenhum histórico encontrado para o vendedor")
    end
  end

  defp test_data_listing do
    IO.puts("\nTeste 5: Listando últimos 5 registros...")

    recent_data = Sales.list_supervisor_data(limit: 5)

    IO.puts("Encontrados #{length(recent_data)} registros:")
    Enum.each(recent_data, fn data ->
      IO.puts("   #{data.collected_at} - Vendas: R$ #{data.sale} (#{data.percentual_sale}%)")
    end)
  end

  defp show_next_steps do
    IO.puts("\nTestes concluídos!")
    IO.puts("\nPróximos passos:")
    IO.puts("   1. Configure a URL da sua API real")
    IO.puts("   2. Teste com: JuruConnect.Api.SupervisorClient.fetch_and_save(\"sua-url\")")
    IO.puts("   3. Configure Oban para sync automático")
    IO.puts("   4. Monitore os logs para acompanhar as coletas")

    show_sync_example()
  end

  defp show_sync_example do
    IO.puts("\nPara configurar sync automático:")
    IO.puts("""
       Sync a cada 2 horas
       JuruConnect.Api.SupervisorClient.start_periodic_sync(
         "https://sua-api.com/supervisores",
         7200
       )

       Para parar
       JuruConnect.Api.SupervisorClient.stop_periodic_sync()
    """)
  end
end

TestSupervisorData.run()
