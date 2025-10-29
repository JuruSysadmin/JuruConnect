defmodule App.CelebrationManager do
  @moduledoc """
  Gerenciador de celebrações baseado em dados reais da API.

  Detecta automaticamente quando metas são atingidas e dispara
  celebrações adequadas baseadas no tipo e magnitude da conquista.

  Inclui sistema de cache para evitar celebrações duplicadas.
  """

  use GenServer

  @cache_ttl_ms 3_600_000

  @celebration_types %{
    daily_goal: %{
      threshold: 100.0,
      message: "Meta Diária Atingida!",
      level: :standard,
      sound: "goal_achieved.mp3"
    },
    seller_daily_goal: %{
      threshold: 100.0,
      message: "Meta Diária Atingida!",
      level: :standard,
      sound: "goal_achieved.mp3"
    },
    hourly_goal: %{
      threshold: 100.0,
      message: "Meta Horária Conquistada!",
      level: :minor,
      sound: "hourly_goal.mp3"
    },
    exceptional_performance: %{
      threshold: 120.0,
      message: "Performance Excepcional!",
      level: :epic,
      sound: "epic_achievement.mp3"
    },
    monthly_milestone: %{
      threshold: 100.0,
      message: "Marco Mensal Alcançado!",
      level: :major,
      sound: "monthly_goal.mp3"
    },
    top_seller: %{
      threshold: 150.0,
      message: "Vendedor Destaque!",
      level: :legendary,
      sound: "top_seller.mp3"
    }
  }

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(_state) do
    schedule_cache_cleanup()
    {:ok, %{
      celebrations_cache: %{},
      daily_notifications: %{}
    }}
  end

  @impl GenServer
  def handle_info(:cleanup_cache, state) do
    current_time = System.monotonic_time(:millisecond)
    today = Date.to_string(Date.utc_today())

    cleaned_cache =
      state.celebrations_cache
      |> Enum.filter(fn {_key, timestamp} ->
        current_time - timestamp < @cache_ttl_ms
      end)
      |> Enum.into(%{})

    cleaned_daily_notifications =
      state.daily_notifications
      |> Enum.filter(fn {_key, date} ->
        date == today
      end)
      |> Enum.into(%{})

    schedule_cache_cleanup()
    {:noreply, %{state |
      celebrations_cache: cleaned_cache,
      daily_notifications: cleaned_daily_notifications
    }}
  end

  @impl GenServer
  def handle_call({:check_celebration_cache, cache_key}, _from, state) do
    current_time = System.monotonic_time(:millisecond)

    case Map.get(state.celebrations_cache, cache_key) do
      nil ->
        new_cache = Map.put(state.celebrations_cache, cache_key, current_time)
        {:reply, :not_found, %{state | celebrations_cache: new_cache}}

      cached_time when current_time - cached_time < @cache_ttl_ms ->
        {:reply, :found, state}

      _expired_time ->
        new_cache = Map.put(state.celebrations_cache, cache_key, current_time)
        {:reply, :not_found, %{state | celebrations_cache: new_cache}}
    end
  end

  @impl GenServer
  def handle_call({:check_daily_notification, store_name}, _from, state) do
    today = Date.to_string(Date.utc_today())
    daily_key = "#{store_name}:#{today}"

    case Map.get(state.daily_notifications, daily_key) do
      nil ->
        new_daily_notifications = Map.put(state.daily_notifications, daily_key, today)
        {:reply, :not_notified, %{state | daily_notifications: new_daily_notifications}}

      ^today ->
        {:reply, :already_notified, state}

      _other_date ->
        new_daily_notifications = Map.put(state.daily_notifications, daily_key, today)
        {:reply, :not_notified, %{state | daily_notifications: new_daily_notifications}}
    end
  end

  def process_api_data(api_data) when is_map(api_data) do
    celebrations = []

    celebrations =
      check_company_goals(celebrations, Map.get(api_data, "companies", []))

    filtered_celebrations =
      Enum.filter(celebrations, &should_send_celebration?/1)

    Enum.each(filtered_celebrations, &broadcast_celebration/1)

    {:ok, filtered_celebrations}
  end

  def process_api_data(_), do: {:ok, []}

  @doc """
  Processa dados de supervisores/vendedores e detecta quando vendedores atingem 100% da meta diária.
  """
  def process_supervisor_data(supervisor_id, supervisor_data) when is_list(supervisor_data) do
    celebrations =
      supervisor_data
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(&check_seller_daily_goal(supervisor_id, &1))

    filtered_celebrations =
      Enum.filter(celebrations, &should_send_celebration?/1)

    Enum.each(filtered_celebrations, &broadcast_celebration/1)

    {:ok, filtered_celebrations}
  end

  def process_supervisor_data(_supervisor_id, _), do: {:ok, []}

  def process_new_sale(_sale_data, _current_totals) do
    {:ok, []}
  end

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, 600_000)
  end

  defp should_send_celebration?(celebration) do
    case celebration.type do
      :daily_goal -> check_daily_goal_notification(celebration)
      :seller_daily_goal -> check_seller_goal_cache(celebration)
      _ -> check_general_cache(celebration)
    end
  rescue
    _error -> true
  end

  defp check_daily_goal_notification(celebration) do
    store_name = get_in(celebration.data, [:store_name]) || "unknown"

    case GenServer.call(__MODULE__, {:check_daily_notification, store_name}) do
      :not_notified -> true
      :already_notified -> false
    end
  end

  defp check_seller_goal_cache(celebration) do
    seller_name = get_in(celebration.data, [:store_name]) || "unknown"
    today = Date.to_string(Date.utc_today())
    cache_key = "seller_daily_goal:#{seller_name}:#{today}"

    case GenServer.call(__MODULE__, {:check_celebration_cache, cache_key}) do
      :not_found -> true
      :found -> false
    end
  end

  defp check_general_cache(celebration) do
    cache_key = create_cache_key(celebration)

    case GenServer.call(__MODULE__, {:check_celebration_cache, cache_key}) do
      :not_found -> true
      :found -> false
    end
  end

  defp create_cache_key(celebration) do
    today = Date.to_string(Date.utc_today())

    create_cache_key_for_type(celebration.type, celebration, today)
  end

  defp create_cache_key_for_type(:daily_goal, celebration, today) do
    store_name = get_cache_store_name(celebration)
    "daily_goal:#{store_name}:#{today}"
  end

  defp create_cache_key_for_type(:hourly_goal, celebration, today) do
    store_name = get_cache_store_name(celebration)
    hour = DateTime.utc_now().hour
    "hourly_goal:#{store_name}:#{today}:#{hour}"
  end

  defp create_cache_key_for_type(:exceptional_performance, celebration, today) do
    store_name = get_cache_store_name(celebration)
    percentage = celebration.percentage
    "exceptional_performance:#{store_name}:#{percentage}:#{today}"
  end

  defp create_cache_key_for_type(:top_seller, celebration, today) do
    seller_name = get_in(celebration.data, [:seller_name]) || "unknown"
    percentage = celebration.percentage
    "top_seller:#{seller_name}:#{percentage}:#{today}"
  end

  defp create_cache_key_for_type(:monthly_milestone, celebration, _today) do
    percentage = celebration.percentage
    month = Date.utc_today() |> Date.beginning_of_month() |> Date.to_string()
    "monthly_milestone:#{percentage}:#{month}"
  end

  defp create_cache_key_for_type(:exceptional_individual_sale, celebration, today) do
    seller_name = get_in(celebration.data, [:seller_name]) || "unknown"
    achieved = get_in(celebration.data, [:achieved]) || 0
    "exceptional_individual_sale:#{seller_name}:#{achieved}:#{today}"
  end

  defp create_cache_key_for_type(:sales_milestone, celebration, today) do
    total_sales = get_in(celebration.data, [:total_sales]) || 0
    milestone = trunc(total_sales / 10_000) * 10_000
    "sales_milestone:#{milestone}:#{today}"
  end

  defp create_cache_key_for_type(:nfs_milestone, celebration, today) do
    nfs_count = get_in(celebration.data, [:nfs_count]) || 0
    "nfs_milestone:#{nfs_count}:#{today}"
  end

  defp create_cache_key_for_type(type, celebration, today) do
    "#{type}:#{celebration.percentage}:#{today}"
  end

  defp get_cache_store_name(celebration) do
    get_in(celebration.data, [:store_name]) || "unknown"
  end

  defp check_company_goals(celebrations, companies) when is_list(companies) do
    new_celebrations =
      companies
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(&check_single_company_goals/1)

    celebrations ++ new_celebrations
  end

  defp check_company_goals(celebrations, _), do: celebrations

  defp check_single_company_goals(company) do
    check_daily_goal([], company)
  end

  defp check_daily_goal(celebrations, company) do
    venda_dia = get_numeric_value(company, :venda_dia, 0.0)
    meta_dia = get_numeric_value(company, :meta_dia, 0.0)

    case meta_dia > 0 and venda_dia > meta_dia do
      true ->
        perc_dia = (venda_dia / meta_dia * 100.0)

        celebration = create_celebration(
          :daily_goal,
          company,
          perc_dia,
          %{
            achieved: venda_dia,
            target: meta_dia,
            store_name: Map.get(company, :nome, "Loja Desconhecida")
          }
        )

        [celebration | celebrations]

      false ->
        celebrations
    end
  end

  defp check_seller_daily_goal(supervisor_id, seller) do
    percentual_objective = get_numeric_value(seller, "percentualObjective", 0.0)
    check_seller_daily_goal(supervisor_id, seller, percentual_objective)
  end

  defp check_seller_daily_goal(supervisor_id, seller, percentual_objective) when percentual_objective >= 100.0 do
    seller_name = Map.get(seller, "sellerName", "Vendedor Desconhecido")
    sale_value = get_numeric_value(seller, "saleValue", 0.0)
    objetivo = get_numeric_value(seller, "objetivo", 0.0)

    celebration = create_celebration(
      :seller_daily_goal,
      seller,
      percentual_objective,
      %{
        achieved: sale_value,
        target: objetivo,
        store_name: seller_name,
        supervisor_id: supervisor_id
      }
    )

    [celebration]
  end

  defp check_seller_daily_goal(_supervisor_id, _seller, _percentual_objective), do: []

  defp create_celebration(type, _data, percentage, extra_data) do
    celebration_config = Map.get(@celebration_types, type)

    safe_percentage =
      case percentage do
        p when is_float(p) -> p
        p when is_integer(p) -> p * 1.0
        p when is_binary(p) ->
          case Float.parse(p) do
            {num, _} -> num
            :error -> 0.0
          end
        _ -> 0.0
      end

    %{
      type: type,
      percentage: Float.round(safe_percentage, 1),
      data: Map.merge(%{
        message: celebration_config.message,
        sound: celebration_config.sound
      }, extra_data),
      timestamp: DateTime.utc_now(),
      celebration_id: System.unique_integer([:positive]),
      level: celebration_config.level
    }
  end

  defp broadcast_celebration(celebration) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      "dashboard:goals",
      {:goal_achieved_real, celebration}
    )
  end

  defp get_numeric_value(data, key, default) when is_map(data) do
    case Map.get(data, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value * 1.0
      value when is_binary(value) ->
        case Float.parse(value) do
          {num, _} -> num
          :error -> ensure_float(default)
        end
      _ -> ensure_float(default)
    end
  end

  defp get_numeric_value(data, key, default) when is_atom(key) do
    get_numeric_value(data, Atom.to_string(key), default)
  end

  defp get_numeric_value(_, _, default), do: ensure_float(default)

  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value * 1.0
  defp ensure_float(_), do: 0.0
end
