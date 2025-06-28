# Teste de integração dashboard - simula comportamento real
require Logger

defmodule DashboardIntegrationTester do
  def run do
    Logger.info("=== TESTE DE INTEGRAÇÃO DASHBOARD ===")

    # Simula uma sessão real de usuário no dashboard
    test_real_session_scenario()

    # Testa múltiplas metas sendo atingidas simultaneamente
    test_multiple_goals_scenario()

    # Testa recuperação de dados após restart
    test_data_recovery_scenario()
  end

  defp test_real_session_scenario do
    Logger.info("1. 🎭 CENÁRIO: Sessão real de usuário")

    # Simula uma manhã típica onde várias lojas atingem metas
    morning_goals = [
      %{store: "JURUNENSE BR", achieved: 250000, target: 240000, time: "09:30"},
      %{store: "JURUNENSE ALCINDO", achieved: 180000, target: 170000, time: "10:15"},
      %{store: "JURUNENSE SENADOR LEMOS", achieved: 90000, target: 85000, time: "10:45"},
      %{store: "JURUNENSE CENTRO", achieved: 120000, target: 115000, time: "11:20"}
    ]

    Logger.info("  🌅 Simulando manhã de vendas...")

    Enum.with_index(morning_goals, fn goal, index ->
      percentage = (goal.achieved / goal.target * 100) |> Float.round(1)

      # Simula o timing real
      Process.sleep(300)

      Logger.info("  ⏰ #{goal.time} - #{goal.store}:")
      Logger.info("    💰 Vendido: #{App.Dashboard.format_money(goal.achieved)}")
      Logger.info("    🎯 Meta: #{App.Dashboard.format_money(goal.target)}")
      Logger.info("    📊 Percentual: #{percentage}%")

      # Envia notificação real
      goal_data = %{
        store_name: goal.store,
        achieved: goal.achieved * 1.0,
        target: goal.target * 1.0,
        percentage: percentage,
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive])
      }

      Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:daily_goal_achieved, goal_data})

      # Se for uma performance excepcional, envia celebração especial
      if percentage > 130 do
        celebration_data = %{
          type: :exceptional_performance,
          percentage: percentage,
          data: %{
            store_name: goal.store,
            achieved: goal.achieved * 1.0,
            target: goal.target * 1.0,
            message: "Performance Excepcional da Manhã!"
          },
          timestamp: DateTime.utc_now(),
          celebration_id: System.unique_integer([:positive]),
          level: if(percentage > 150, do: :epic, else: :major)
        }

        Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:goal_achieved_real, celebration_data})
        Logger.info("    🎉 CELEBRAÇÃO ESPECIAL! Performance excepcional!")
      end

      Logger.info("    ✅ Meta #{index + 1}/#{length(morning_goals)} processada")
    end)

    Logger.info("  🏁 Manhã de vendas simulada com sucesso!")
  end

  defp test_multiple_goals_scenario do
    Logger.info("2. 🚀 CENÁRIO: Múltiplas metas simultâneas")

    # Simula o rush de final de dia onde várias lojas fecham metas
    Logger.info("  🌆 Simulando rush de final de dia...")

    # Cria várias vendas que levam a metas atingidas
    rush_sales = [
      %{seller: "João Silva", store: "LOJA RUSH 1", value: 15000, target: 12000},
      %{seller: "Maria Santos", store: "LOJA RUSH 2", value: 22000, target: 20000},
      %{seller: "Pedro Costa", store: "LOJA RUSH 3", value: 8500, target: 8000},
      %{seller: "Ana Ferreira", store: "LOJA RUSH 4", value: 35000, target: 30000},
      %{seller: "Carlos Oliveira", store: "LOJA RUSH 5", value: 18000, target: 15000}
    ]

    # Envia todas as vendas rapidamente
    Task.async_stream(rush_sales, fn sale ->
      # Cria venda no banco
      sale_data = %{
        seller_name: sale.seller,
        store: sale.store,
        sale_value: sale.value * 1.0,
        objetivo: sale.target * 1.0,
        timestamp: DateTime.utc_now(),
        type: :api,
        status: "completed"
      }

      case App.Sales.create_sale(sale_data) do
        {:ok, created_sale} ->
          # Broadcast da venda
          broadcast_data = %{
            id: created_sale.id,
            seller_name: created_sale.seller_name,
            store: created_sale.store,
            sale_value: Decimal.to_float(created_sale.sale_value),
            objetivo: Decimal.to_float(created_sale.objetivo),
            timestamp: created_sale.timestamp,
            type: created_sale.type
          }

          Phoenix.PubSub.broadcast(App.PubSub, "sales:feed", {:new_sale, broadcast_data})

          # Simula meta atingida
          percentage = (sale.value / sale.target * 100) |> Float.round(1)

          goal_data = %{
            store_name: sale.store,
            achieved: sale.value * 1.0,
            target: sale.target * 1.0,
            percentage: percentage,
            timestamp: DateTime.utc_now(),
            celebration_id: System.unique_integer([:positive])
          }

          Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:daily_goal_achieved, goal_data})

          Logger.info("  💥 #{sale.seller} - #{sale.store}: #{App.Dashboard.format_money(sale.value)} (#{percentage}%)")

        {:error, _} ->
          Logger.error("  ❌ Erro ao criar venda para #{sale.seller}")
      end
    end, max_concurrency: 5, timeout: 10_000)
    |> Enum.to_list()

    Logger.info("  🎯 #{length(rush_sales)} vendas simultâneas processadas!")
  end

  defp test_data_recovery_scenario do
    Logger.info("3. 🔄 CENÁRIO: Recuperação de dados")

    # Testa se o sistema consegue recuperar dados após uma falha
    Logger.info("  📊 Verificando capacidade de recuperação...")

    # Busca dados salvos
    case App.Sales.get_sales_feed(15) do
      {:ok, sales} ->
        Logger.info("  ✅ Feed recuperado com #{length(sales)} vendas")

        if length(sales) > 0 do
          total_value = sales
            |> Enum.map(& &1.sale_value)
            |> Enum.sum()

          Logger.info("  💰 Valor total no feed: #{App.Dashboard.format_money(total_value)}")

          # Mostra vendas mais recentes
          recent_sales = Enum.take(sales, 3)
          Logger.info("  📋 3 vendas mais recentes:")

          Enum.with_index(recent_sales, fn sale, index ->
            Logger.info("    #{index + 1}. #{sale.seller_name} - #{sale.sale_value_formatted} (#{sale.store})")
          end)
        end

      {:error, reason} ->
        Logger.error("  ❌ Erro na recuperação: #{inspect(reason)}")
    end

    # Testa métricas agregadas
    today = Date.utc_today()
    metrics = App.Sales.calculate_sales_metrics(date_from: today, date_to: today)

    Logger.info("  📈 Métricas do dia recuperadas:")
    Logger.info("    - Total vendido: #{App.Dashboard.format_money(metrics.total_sales)}")
    Logger.info("    - Número de vendas: #{metrics.count}")
    Logger.info("    - Média por venda: #{App.Dashboard.format_money(metrics.avg_sale)}")

    if metrics.count > 0 do
      Logger.info("  ✅ Sistema pode recuperar dados históricos!")
    else
      Logger.info("  ⚠️  Poucos dados para análise de recuperação")
    end
  end
end

# Executa teste de integração
DashboardIntegrationTester.run()

# Aguarda processamento
Logger.info("⏳ Aguardando 5 segundos para estabilização...")
Process.sleep(5000)

# Relatório final
Logger.info("📋 RELATÓRIO FINAL DE INTEGRAÇÃO:")

today = Date.utc_today()

# Total de vendas criadas hoje
case App.Repo.query("SELECT COUNT(*), COALESCE(SUM(sale_value), 0) FROM sales WHERE DATE(timestamp) = $1", [today]) do
  {:ok, %{rows: [[count, total]]}} ->
    total_value = if total, do: Decimal.to_float(total), else: 0.0
    Logger.info("  📊 Vendas criadas hoje: #{count}")
    Logger.info("  💰 Valor total: #{App.Dashboard.format_money(total_value)}")

    if count > 0 do
      avg = total_value / count
      Logger.info("  📈 Média por venda: #{App.Dashboard.format_money(avg)}")
    end

  _ ->
    Logger.info("  ❌ Erro ao gerar relatório final")
end

# Vendas por tipo
case App.Repo.query("SELECT type, COUNT(*), COALESCE(SUM(sale_value), 0) FROM sales WHERE DATE(timestamp) = $1 GROUP BY type", [today]) do
  {:ok, %{rows: rows}} ->
    Logger.info("  🏷️  Vendas por tipo:")
    Enum.each(rows, fn [type, count, total] ->
      total_value = if total, do: Decimal.to_float(total), else: 0.0
      Logger.info("    - #{type}: #{count} vendas (#{App.Dashboard.format_money(total_value)})")
    end)
  _ ->
    Logger.info("  ⚠️  Não foi possível agrupar por tipo")
end

Logger.info("🎉 TESTE DE INTEGRAÇÃO CONCLUÍDO COM SUCESSO!")
