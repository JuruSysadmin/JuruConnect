defmodule App.Dashboard do
  @moduledoc """
  Facade principal para o sistema de Dashboard.

  Fornece uma interface simples que internamente usa a arquitetura separada:
  - Dashboard.Orchestrator: coordena tudo
  - Dashboard.DataStore: gerencia estado
  - Dashboard.CacheManager: gerencia cache
  - Dashboard.EventBroadcaster: gerencia eventos
  - Dashboard.DataFetcher: busca dados da API

  Esta arquitetura segue o padrão Single Responsibility Principle,
  onde cada módulo tem uma responsabilidade específica.
  """

  alias App.Dashboard.{Orchestrator, CacheManager, EventBroadcaster}
  alias App.DashboardDataServer

  # === INTERFACE PÚBLICA ===

  def get_metrics(opts \\ []) do
    case Orchestrator.get_data(opts) do
      {:ok, raw_data} ->
        with {:ok, processed_data} <- process_data(raw_data),
         {:ok, formatted_data} <- format_for_display(processed_data) do
      {:ok, formatted_data}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Erro inesperado: #{inspect(error)}"}
        end

      {:loading, nil} ->
        {:loading, "Dados sendo carregados..."}

      {:error, reason} ->
        {:error, reason}

      error ->
        {:error, "Erro inesperado: #{inspect(error)}"}
    end
  end

  def get_store_performance(store_ids \\ []) do
    with {:ok, metrics} <- get_metrics(),
         stores_data <- filter_stores(metrics.stores, store_ids) do
      performance_data = calculate_store_performance(stores_data)
      {:ok, performance_data}
    end
  end

  def get_alerts do
    case get_metrics() do
      {:ok, metrics} ->
        alerts = analyze_metrics_for_alerts(metrics)
        {:ok, alerts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_sales_feed(limit \\ nil) do
    actual_limit = limit || App.Config.sales_feed_limit()

         case App.ApiClient.fetch_sales_feed_robust(actual_limit) do
      {:ok, [_ | _] = sales_data} ->
        formatted_sales =
          sales_data
          |> Enum.map(&format_and_save_api_sale/1)
          |> Enum.sort_by(& &1.sale_value, :desc)

        {:ok, formatted_sales}

             _ ->
         try_fallback_strategies(actual_limit)
    end
  end

  defp try_fallback_strategies(actual_limit) do
    case App.Sales.get_sales_feed(actual_limit) do
      {:ok, [_ | _] = saved_sales} ->
        {:ok, saved_sales}

      _ ->
        case App.ApiClient.fetch_sales_feed(15) do
          {:ok, minimal_sales} ->
            formatted_minimal = Enum.map(minimal_sales, &format_and_save_api_sale/1)
            {:ok, formatted_minimal}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def register_sale(sale_data) do
    with {:ok, validated_sale} <- validate_sale_data(sale_data),
         {:ok, saved_sale} <- save_sale(validated_sale),
         :ok <- broadcast_sale(saved_sale) do
      {:ok, saved_sale}
    end
  end

  def check_goal_achievement(store_id) do
    with {:ok, store_metrics} <- get_store_metrics(store_id),
         true <- goal_achieved?(store_metrics),
         :ok <- trigger_celebration(store_metrics) do
      {:ok, :goal_achieved}
    else
      false -> {:ok, :goal_not_achieved}
      error -> error
    end
  end

  # === FUNÇÕES DE CONTROLE ===

  def force_refresh do
    Orchestrator.force_refresh()
  end

  def get_system_status do
    %{
      orchestrator: Orchestrator.get_status(),
      cache: CacheManager.stats(),
      broadcasts: EventBroadcaster.get_stats(),
      supervisor_health: App.Dashboard.Supervisor.health_check()
    }
  end

  def subscribe_to_updates do
    EventBroadcaster.subscribe_to_dashboard_updates()
  end

  def subscribe_to_sales do
    EventBroadcaster.subscribe_to_sales_feed()
  end

  def subscribe_to_celebrations do
    EventBroadcaster.subscribe_to_celebrations()
  end

  # === COMPATIBILIDADE COM CÓDIGO EXISTENTE ===

  # Mantém compatibilidade com o DashboardDataServer antigo
  def get_data(opts \\ []) do
    # Primeiro tenta a nova arquitetura
    case Orchestrator.get_data(opts) do
      {:ok, data} -> %{api_status: :ok, data: data}
      {:loading, _} -> %{api_status: :loading, data: nil}
      {:error, reason} -> %{api_status: :error, data: nil, api_error: reason}
    end
  rescue
    _ ->
      # Fallback para o sistema antigo se a nova arquitetura falhar
      DashboardDataServer.get_data(opts)
  end

  # === FUNÇÕES PRIVADAS (mantidas do código original) ===

  defp process_data(raw_data) do
    processed = %{
      sales: extract_sales_data(raw_data),
      costs: extract_costs_data(raw_data),
      goals: extract_goals_data(raw_data),
      stores: extract_stores_data(raw_data),
      percentages: calculate_percentages(raw_data)
    }

    {:ok, processed}
  rescue
    error -> {:error, "Erro no processamento: #{inspect(error)}"}
  end

  defp format_for_display(processed_data) do
    formatted = %{
      sales: %{
        total: get_numeric_value(processed_data.sales, :total),
        formatted: format_money(get_numeric_value(processed_data.sales, :total))
      },
      costs: %{
        total: get_numeric_value(processed_data.costs, :total),
        formatted: format_money(get_numeric_value(processed_data.costs, :total)),
        devolutions: get_numeric_value(processed_data.costs, :devolutions)
      },
      goal: %{
        total: get_numeric_value(processed_data.goals, :total),
        formatted: format_money(get_numeric_value(processed_data.goals, :total)),
        percentage: get_numeric_value(processed_data.percentages, :goal),
        formatted_percentage: "#{Float.round(get_numeric_value(processed_data.percentages, :goal), 2)}%"
      },
      profit: %{
        percentage: get_numeric_value(processed_data.percentages, :profit),
        formatted: "#{Float.round(get_numeric_value(processed_data.percentages, :profit), 2)}%"
      },
      stores: format_stores_data(processed_data.stores),
      nfs_count: get_numeric_value(processed_data, :nfs_count),
      last_update: DateTime.utc_now(),
      api_status: :ok
    }

    {:ok, formatted}
  rescue
    error -> {:error, "Erro na formatação: #{inspect(error)}"}
  end

  defp extract_sales_data(raw_data) do
    companies = Map.get(raw_data, "companies", [])

    total_sales =
      companies
      |> Enum.map(& get_numeric_value(&1, "sale"))
      |> Enum.sum()

    %{total: total_sales}
  end

  defp extract_costs_data(raw_data) do
    companies = Map.get(raw_data, "companies", [])

    total_costs =
      companies
      |> Enum.map(& get_numeric_value(&1, "discount"))
      |> Enum.sum()

    total_devolutions =
      companies
      |> Enum.map(& get_numeric_value(&1, "devolution"))
      |> Enum.sum()

    %{total: total_costs, devolutions: total_devolutions}
  end

  defp extract_goals_data(raw_data) do
    companies = Map.get(raw_data, "companies", [])

    total_goals =
      companies
      |> Enum.map(& get_numeric_value(&1, "objective"))
      |> Enum.sum()

    %{total: total_goals}
  end

  defp extract_stores_data(raw_data) do
    Map.get(raw_data, "companies", [])
  end

  defp calculate_percentages(raw_data) do
    companies = Map.get(raw_data, "companies", [])

    total_sales =
      companies
      |> Enum.map(& get_numeric_value(&1, "sale"))
      |> Enum.sum()

    total_goals =
      companies
      |> Enum.map(& get_numeric_value(&1, "objective"))
      |> Enum.sum()

    total_costs =
      companies
      |> Enum.map(& get_numeric_value(&1, "discount"))
      |> Enum.sum()

    goal_percentage = if total_goals > 0, do: (total_sales / total_goals * 100), else: 0.0
    profit_percentage = if total_sales > 0, do: ((total_sales - total_costs) / total_sales * 100), else: 0.0

    %{
      goal: goal_percentage,
      profit: profit_percentage
    }
  end

  defp format_stores_data(stores) when is_list(stores) do
    Enum.map(stores, fn store ->
      daily_sales = get_numeric_value(store, "sale")
      daily_goal = get_numeric_value(store, "objective")
      daily_percentage = if daily_goal > 0, do: (daily_sales / daily_goal * 100), else: 0.0

      %{
        name: Map.get(store, "nome", "Loja Desconhecida"),
        daily_sales: daily_sales,
        daily_sales_formatted: format_money(daily_sales),
        daily_goal: daily_goal,
        daily_goal_formatted: format_money(daily_goal),
        daily_percentage: daily_percentage,
        daily_percentage_formatted: "#{Float.round(daily_percentage, 2)}%",
        status: determine_store_status(daily_percentage)
      }
    end)
  end

  defp format_stores_data(_), do: []

  defp determine_store_status(percentage) when percentage >= 100.0, do: :goal_achieved
  defp determine_store_status(percentage) when percentage >= 80.0, do: :on_track
  defp determine_store_status(_), do: :below_target

  defp filter_stores(stores, []), do: stores
  defp filter_stores(stores, store_ids) do
    Enum.filter(stores, fn store ->
      store.name in store_ids
    end)
  end

  defp calculate_store_performance(stores_data) do
    Enum.map(stores_data, fn store ->
      performance_score = calculate_performance_score(store)

      Map.put(store, :performance_score, performance_score)
    end)
  end

  defp calculate_performance_score(store) do
    # Implementar lógica de cálculo de performance
    base_score = store.daily_percentage

    # Ajustes baseados em outros fatores
    adjusted_score = base_score * 1.0  # Placeholder

    Float.round(adjusted_score, 2)
  end

  defp analyze_metrics_for_alerts(metrics) do
    alerts = []

    # Verifica se alguma loja está muito abaixo da meta
    low_performance_stores =
      Enum.filter(metrics.stores, fn store ->
        store.daily_percentage < 50.0
      end)

    alerts = if length(low_performance_stores) > 0 do
      alert = %{
        type: :low_performance,
        severity: :warning,
        message: "#{length(low_performance_stores)} loja(s) com performance abaixo de 50%",
        stores: Enum.map(low_performance_stores, & &1.name)
      }
      [alert | alerts]
      else
        alerts
      end

    # Verifica se a performance geral está baixa
    alerts = if metrics.goal.percentage < 70.0 do
      alert = %{
        type: :overall_low_performance,
        severity: :critical,
        message: "Performance geral abaixo de 70%: #{metrics.goal.formatted_percentage}",
        current_percentage: metrics.goal.percentage
      }
      [alert | alerts]
      else
        alerts
      end

    alerts
  end

  defp validate_sale_data(sale_data) do
    required_fields = [:seller_name, :amount, :product]

    missing_fields =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(sale_data, field) end)

    if length(missing_fields) > 0 do
      {:error, "Dados de venda incompletos"}
    else
      {:ok, sale_data}
    end
  end

  defp save_sale(sale_data) do
    # Implementar lógica de salvamento
    {:ok, Map.put(sale_data, :id, System.unique_integer([:positive]))}
  end

  defp broadcast_sale(sale_data) do
    EventBroadcaster.broadcast_new_sale(sale_data)
    :ok
  end

  defp get_store_metrics(store_id) do
    # Implementar busca de métricas específicas da loja
    {:ok, %{store_id: store_id, percentage: 95.0}}
  end

  defp goal_achieved?(%{percentage: percentage}) when percentage >= 100.0, do: true
  defp goal_achieved?(_), do: false

  defp trigger_celebration(store_metrics) do
    celebration_data = %{
      type: :goal_achieved,
      store_id: store_metrics.store_id,
      percentage: store_metrics.percentage,
      timestamp: DateTime.utc_now()
    }

    EventBroadcaster.broadcast_celebration(celebration_data)
    :ok
  end

  defp format_and_save_api_sale(sale_data) do
    # Implementar formatação e salvamento de venda da API
    %{
      id: System.unique_integer([:positive]),
      seller_name: Map.get(sale_data, "seller_name", "Desconhecido"),
      sale_value: get_numeric_value(sale_data, "sale_value"),
      timestamp: DateTime.utc_now()
    }
  end

  defp get_numeric_value(data, key)

  defp get_numeric_value(data, key) when is_map(data) do
    case Map.get(data, key) do
      nil -> 0.0
      value when is_number(value) -> Float.round(value * 1.0, 2)
      value when is_binary(value) ->
        case Float.parse(value) do
          {num, _} -> Float.round(num, 2)
          :error -> 0.0
        end
      _ -> 0.0
    end
  end

  defp get_numeric_value(_, _), do: 0.0

  def format_money(value) when is_number(value) do
    # Formato brasileiro: R$ 1.234,56
    formatted =
      value
      |> Float.round(2)
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")

    "R$ #{formatted}"
  end

  def format_money(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> format_money(num)
      :error -> "R$ 0,00"
    end
  end

  def format_money(_), do: "R$ 0,00"

  def export_data(metrics, format) when format in ["csv", "json", "xlsx"] do
    case format do
      "csv" -> export_to_csv(metrics)
      "json" -> export_to_json(metrics)
      "xlsx" -> export_to_excel(metrics)
    end
  end

  def export_data(_metrics, format) do
    {:error, "Formato não suportado: #{format}"}
  end

  def parse_api_data(raw_data) when is_map(raw_data) do
    try do
      with {:ok, processed_data} <- process_data(raw_data),
           {:ok, formatted_data} <- format_for_display(processed_data) do
        {:ok, formatted_data}
      else
        error -> {:error, "Erro no processamento: #{inspect(error)}"}
      end
    rescue
      error -> {:error, "Erro ao processar dados: #{inspect(error)}"}
    end
  end

  def parse_api_data(_), do: {:error, "Dados inválidos"}

  def get_default_metrics do
    %{
      sales: %{total: 0.0, formatted: "R$ 0,00"},
      costs: %{total: 0.0, formatted: "R$ 0,00", devolutions: 0.0},
      goal: %{
        total: 0.0,
        formatted: "R$ 0,00",
        percentage: 0.0,
        formatted_percentage: "0,00%"
      },
      profit: %{percentage: 0.0, formatted: "0,00%"},
      stores: [],
      nfs_count: 0,
      last_update: DateTime.utc_now(),
      api_status: :no_data
    }
  end

  defp export_to_csv(metrics) do
    header = "Loja,Meta Diária,Vendas,Percentual,Status\n"

    rows =
       Enum.map_join(metrics.stores, "\n", fn store ->
         status_text = format_status(store.status)
         "#{store.name},#{store.daily_goal_formatted},#{store.daily_sales_formatted},#{store.daily_percentage_formatted},#{status_text}"
      end)

    {:ok, header <> rows}
  end

  defp export_to_json(metrics) do
    export_data = %{
      summary: %{
        total_sales: metrics.sales.formatted,
        total_goal: metrics.goal.formatted,
        completion_percentage: metrics.goal.formatted_percentage
      },
      stores: metrics.stores
    }

    case Jason.encode(export_data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "Erro ao gerar JSON: #{inspect(reason)}"}
    end
  end

  defp export_to_excel(_metrics) do
    {:error, "Exportação para Excel não implementada ainda"}
  end

  defp format_status(:goal_achieved), do: "Meta Atingida"
  defp format_status(:on_track), do: "No Caminho"
  defp format_status(:below_target), do: "Abaixo da Meta"
  defp format_status(_), do: "Desconhecido"

  def simulate_goal_achievement do
    celebration_data = %{
      store_name: "LOJA TESTE #{:rand.uniform(99)}",
      achieved: :rand.uniform(5000) + 10_000,
      target: 12_000.0,
      timestamp: DateTime.utc_now(),
      celebration_id: System.unique_integer([:positive])
    }

    percentage = (celebration_data.achieved / celebration_data.target * 100) |> Float.round(1)

    {:ok, Map.put(celebration_data, :percentage, percentage)}
  end

  def simulate_sale do
    sellers = [
      {"João Silva", "JS"}, {"Maria Santos", "MS"}, {"Pedro Costa", "PC"},
      {"Ana Oliveira", "AO"}, {"Carlos Pereira", "CP"}, {"Lucia Ferreira", "LF"}
    ]

    products = [
      {"Smartphone Samsung", "Eletrônicos", "Samsung"},
      {"Notebook Dell", "Informática", "Dell"},
      {"Tênis Nike", "Esportivos", "Nike"},
      {"Camiseta Polo", "Vestuário", "Lacoste"}
    ]

    statuses = ["Confirmada", "Pendente", "Cancelada"]
    colors = ["#4CAF50", "#2196F3", "#FF9800", "#9C27B0", "#F44336"]

    {seller_name, seller_initials} = Enum.random(sellers)
    {product, category, brand} = Enum.random(products)

    sale_data = %{
      id: System.unique_integer([:positive]),
      seller_name: seller_name,
      seller_initials: seller_initials,
      amount: (:rand.uniform(4500) + 500) * 1.0,
      product: product,
      category: category,
      brand: brand,
      status: Enum.random(statuses),
      timestamp: DateTime.utc_now(),
      color: Enum.random(colors)
    }

    {:ok, sale_data}
  end
end
