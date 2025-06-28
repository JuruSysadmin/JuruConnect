# Script de teste completo para notificações e celebrações
require Logger

defmodule TestCompleteNotifications do
  import Ecto.Query
  alias App.Repo
  alias App.Schemas.Sale
  alias JuruConnect.Schemas.SupervisorData

  def run do
    Logger.info("=== TESTE COMPLETO DO SISTEMA DE NOTIFICAÇÕES ===")

    # Teste 1: Verificar dados atuais
    test_current_data()

    # Teste 2: Teste do PubSub
    test_pubsub_system()

    # Teste 3: Teste de celebrações
    test_celebration_system()

    # Teste 4: Teste de persistência
    test_persistence_system()

    # Teste 5: Teste da API de vendas
    test_sales_api()

    # Teste 6: Teste de métricas
    test_metrics_calculation()

    Logger.info("=== TESTE CONCLUÍDO ===")
  end

  defp test_current_data do
    Logger.info("\n🔍 TESTE 1: Verificando Dados Atuais")

    today = Date.utc_today()

    # Vendas individuais hoje
    today_sales = Sale
      |> where([s], fragment("DATE(?)", s.timestamp) == ^today)
      |> Repo.all()

    Logger.info("   📊 Vendas individuais hoje: #{length(today_sales)}")

    # Dados agregados hoje
    supervisor_data = SupervisorData
      |> where([s], fragment("DATE(?)", s.collected_at) == ^today)
      |> order_by(desc: :collected_at)
      |> limit(1)
      |> Repo.one()

    if supervisor_data do
      sale_today = Decimal.to_float(supervisor_data.sale_today || Decimal.new(0))
      objective_today = Decimal.to_float(supervisor_data.objective_today || Decimal.new(0))
      percentage = if objective_today > 0, do: (sale_today / objective_today * 100), else: 0.0

      Logger.info("   📈 Dados agregados mais recentes:")
      Logger.info("   - Vendas hoje: #{App.Dashboard.format_money(sale_today)}")
      Logger.info("   - Meta hoje: #{App.Dashboard.format_money(objective_today)}")
      Logger.info("   - Percentual: #{Float.round(percentage, 1)}%")
      Logger.info("   - Status: #{if percentage >= 100, do: "✅ META ATINGIDA!", else: "⏳ Em progresso"}")
    else
      Logger.info("   ❌ Nenhum dado agregado encontrado hoje")
    end
  end

  defp test_pubsub_system do
    Logger.info("\n📡 TESTE 2: Sistema PubSub")

    # Subscreve aos tópicos para testar
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
    Phoenix.PubSub.subscribe(App.PubSub, "sales:feed")

    Logger.info("   ✅ Subscrito aos tópicos: dashboard:updated, dashboard:goals, sales:feed")

    # Testa broadcast de meta atingida
    test_goal_data = %{
      store_name: "LOJA TESTE NOTIFICAÇÃO",
      achieved: 150000.0,
      target: 100000.0,
      percentage: 150.0,
      timestamp: DateTime.utc_now(),
      celebration_id: System.unique_integer([:positive])
    }

    Logger.info("   🚀 Enviando teste de meta atingida...")
    Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:daily_goal_achieved, test_goal_data})

    # Espera um pouco para processar
    Process.sleep(100)

    Logger.info("   ✅ Broadcast de teste enviado com sucesso!")
  end

  defp test_celebration_system do
    Logger.info("\n🎉 TESTE 3: Sistema de Celebrações")

    # Testa diferentes tipos de celebração
    celebration_types = [
      %{
        type: :daily_goal_achieved,
        data: %{
          store_name: "LOJA TESTE DIÁRIA",
          achieved: 200000.0,
          target: 180000.0,
          percentage: 111.1
        }
      },
      %{
        type: :exceptional_performance,
        data: %{
          store_name: "LOJA TESTE EXCEPCIONAL",
          achieved: 500000.0,
          target: 200000.0,
          percentage: 250.0
        }
      }
    ]

    Enum.each(celebration_types, fn celebration ->
      Logger.info("   🎊 Testando celebração: #{celebration.type}")

      celebration_data = %{
        type: celebration.type,
        percentage: celebration.data.percentage,
        data: celebration.data,
        timestamp: DateTime.utc_now(),
        celebration_id: System.unique_integer([:positive]),
        level: determine_celebration_level(celebration.data.percentage)
      }

      Phoenix.PubSub.broadcast(App.PubSub, "dashboard:goals", {:goal_achieved_real, celebration_data})
      Logger.info("   ✅ Celebração #{celebration.type} enviada")
    end)
  end

  defp test_persistence_system do
    Logger.info("\n💾 TESTE 4: Sistema de Persistência")

    # Testa criação de venda via API
    api_sale_data = %{
      seller_name: "VENDEDOR TESTE API",
      store: "LOJA TESTE PERSISTÊNCIA",
      sale_value: 3500.00,
      objetivo: 3000.00,
      timestamp: DateTime.utc_now(),
      type: :api,
      status: "completed"
    }

    Logger.info("   📝 Testando criação de venda via API...")

    case App.Sales.create_sale(api_sale_data) do
      {:ok, sale} ->
        Logger.info("   ✅ Venda criada com sucesso! ID: #{sale.id}")
        Logger.info("   - Vendedor: #{sale.seller_name}")
        Logger.info("   - Valor: #{App.Dashboard.format_money(Decimal.to_float(sale.sale_value))}")
        Logger.info("   - Tipo: #{sale.type}")

        # Testa broadcast da venda
        broadcast_data = %{
          id: sale.id,
          seller_name: sale.seller_name,
          store: sale.store,
          sale_value: Decimal.to_float(sale.sale_value),
          objetivo: Decimal.to_float(sale.objetivo || Decimal.new(0)),
          timestamp: sale.timestamp,
          type: sale.type
        }

        Phoenix.PubSub.broadcast(App.PubSub, "sales:feed", {:new_sale, broadcast_data})
        Logger.info("   📡 Broadcast da venda enviado")

      {:error, changeset} ->
        Logger.error("   ❌ Erro ao criar venda: #{inspect(changeset.errors)}")
    end
  end

  defp test_sales_api do
    Logger.info("\n🌐 TESTE 5: API de Vendas")

    Logger.info("   🔄 Testando busca de vendas da API...")

    case App.Dashboard.get_sales_feed(5) do
      {:ok, sales} ->
        Logger.info("   ✅ API respondeu com #{length(sales)} vendas")

        if length(sales) > 0 do
          sale = List.first(sales)
          Logger.info("   📊 Primeira venda:")
          Logger.info("   - Vendedor: #{sale.seller_name}")
          Logger.info("   - Loja: #{sale.store}")
          Logger.info("   - Valor: #{sale.sale_value_formatted}")
          Logger.info("   - Tipo: #{sale.type}")
        end

      {:error, reason} ->
        Logger.error("   ❌ Erro na API: #{inspect(reason)}")
        Logger.info("   🔄 Testando fallback para dados salvos...")

        case App.Sales.get_sales_feed(5) do
          {:ok, saved_sales} ->
            Logger.info("   ✅ Fallback funcionou! #{length(saved_sales)} vendas salvas")
          {:error, fallback_reason} ->
            Logger.error("   ❌ Fallback também falhou: #{inspect(fallback_reason)}")
        end
    end
  end

  defp test_metrics_calculation do
    Logger.info("\n📈 TESTE 6: Cálculo de Métricas")

    Logger.info("   🧮 Calculando métricas de vendas...")

    today = Date.utc_today()
    metrics = App.Sales.calculate_sales_metrics(
      date_from: today,
      date_to: today
    )

    Logger.info("   ✅ Métricas calculadas:")
    Logger.info("   - Total de vendas: #{App.Dashboard.format_money(metrics.total_sales)}")
    Logger.info("   - Total de objetivos: #{App.Dashboard.format_money(metrics.total_objetivo)}")
    Logger.info("   - Número de vendas: #{metrics.count}")
    Logger.info("   - Média por venda: #{App.Dashboard.format_money(metrics.avg_sale)}")

    # Testa métricas dos últimos 7 dias
    seven_days_ago = Date.add(today, -7)
    weekly_metrics = App.Sales.calculate_sales_metrics(
      date_from: seven_days_ago,
      date_to: today
    )

    Logger.info("   📅 Métricas dos últimos 7 dias:")
    Logger.info("   - Total: #{App.Dashboard.format_money(weekly_metrics.total_sales)}")
    Logger.info("   - Vendas: #{weekly_metrics.count}")
  end

  defp determine_celebration_level(percentage) when percentage >= 200.0, do: :legendary
  defp determine_celebration_level(percentage) when percentage >= 150.0, do: :epic
  defp determine_celebration_level(percentage) when percentage >= 120.0, do: :major
  defp determine_celebration_level(percentage) when percentage >= 100.0, do: :standard
  defp determine_celebration_level(_), do: :minor
end

# Função para escutar mensagens PubSub durante os testes
defmodule TestPubSubListener do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:updated")
    Phoenix.PubSub.subscribe(App.PubSub, "dashboard:goals")
    Phoenix.PubSub.subscribe(App.PubSub, "sales:feed")
    Logger.info("   👂 Listener PubSub iniciado")
    {:ok, %{}}
  end

  def handle_info({:daily_goal_achieved, data}, state) do
    Logger.info("   🔔 NOTIFICAÇÃO RECEBIDA: Meta diária atingida")
    Logger.info("   - Loja: #{data.store_name}")
    Logger.info("   - Valor: #{App.Dashboard.format_money(data.achieved)}")
    Logger.info("   - Percentual: #{data.percentage}%")
    {:noreply, state}
  end

  def handle_info({:goal_achieved_real, data}, state) do
    Logger.info("   🔔 NOTIFICAÇÃO RECEBIDA: Celebração real")
    Logger.info("   - Tipo: #{data.type}")
    Logger.info("   - Nível: #{data.level}")
    Logger.info("   - Loja: #{get_in(data.data, [:store_name])}")
    {:noreply, state}
  end

  def handle_info({:new_sale, data}, state) do
    Logger.info("   🔔 NOTIFICAÇÃO RECEBIDA: Nova venda")
    Logger.info("   - Vendedor: #{data.seller_name}")
    Logger.info("   - Valor: #{App.Dashboard.format_money(data.sale_value)}")
    Logger.info("   - Tipo: #{data.type}")
    {:noreply, state}
  end

  def handle_info({:dashboard_updated, _data}, state) do
    Logger.info("   🔔 NOTIFICAÇÃO RECEBIDA: Dashboard atualizado")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("   📩 Mensagem não tratada: #{inspect(msg)}")
    {:noreply, state}
  end
end

# Inicia o listener e executa os testes
Logger.info("🚀 Iniciando listener PubSub...")
{:ok, _pid} = TestPubSubListener.start_link([])

Process.sleep(500)  # Aguarda o listener inicializar

TestCompleteNotifications.run()

# Aguarda um pouco para capturar notificações
Logger.info("\n⏳ Aguardando notificações por 3 segundos...")
Process.sleep(3000)

Logger.info("✅ TODOS OS TESTES CONCLUÍDOS!")
