defmodule JuruConnect.Sales do
  @moduledoc """
  Context para gerenciar dados de vendas de supervisores.

  Fornece funções para salvar dados vindos da API e realizar consultas
  otimizadas nos dados históricos.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias JuruConnect.Schemas.SupervisorData

  @spec create_supervisor_data(map()) :: {:ok, SupervisorData.t()} | {:error, Ecto.Changeset.t()}
  def create_supervisor_data(attrs) do
    attrs_with_timestamp = Map.put(attrs, :collected_at, DateTime.utc_now())

    %SupervisorData{}
    |> SupervisorData.changeset(attrs_with_timestamp)
    |> Repo.insert()
  end

  @spec create_supervisor_data_from_api(map()) :: {:ok, SupervisorData.t()} | {:error, Ecto.Changeset.t()}
  def create_supervisor_data_from_api(api_data) do
    normalized_data = normalize_api_data(api_data)
    create_supervisor_data(normalized_data)
  end

  @spec list_supervisor_data(keyword()) :: [SupervisorData.t()]
  def list_supervisor_data(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)

    SupervisorData
    |> maybe_filter_by_date_range(date_from, date_to)
    |> order_by(desc: :collected_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_latest_supervisor_data() :: SupervisorData.t() | nil
  def get_latest_supervisor_data do
    SupervisorData
    |> order_by(desc: :collected_at)
    |> limit(1)
    |> Repo.one()
  end

  @spec get_top_performers(integer(), DateTime.t(), DateTime.t()) :: [map()]
  def get_top_performers(limit \\ 10, date_from, date_to) do
    from(sd in SupervisorData,
      where: sd.collected_at >= ^date_from and sd.collected_at <= ^date_to,
      order_by: [desc: sd.collected_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> []
      data ->
        data.sale_supervisor
        |> Stream.sort_by(& &1["percentualObjective"], :desc)
        |> Enum.take(limit)
    end
  end

  @spec get_seller_history(integer(), DateTime.t(), DateTime.t()) :: [map()]
  def get_seller_history(seller_id, date_from, date_to) do
    from(sd in SupervisorData,
      where: sd.collected_at >= ^date_from and sd.collected_at <= ^date_to,
      order_by: [desc: sd.collected_at]
    )
    |> Repo.all()
    |> Enum.map(fn data ->
      seller_data = Enum.find(data.sale_supervisor, &(&1["sellerId"] == seller_id))

      %{
        collected_at: data.collected_at,
        seller_data: seller_data
      }
    end)
    |> Enum.filter(& &1.seller_data)
  end

  defp maybe_filter_by_date_range(query, nil, nil), do: query
  defp maybe_filter_by_date_range(query, date_from, nil) do
    where(query, [sd], sd.collected_at >= ^date_from)
  end
  defp maybe_filter_by_date_range(query, nil, date_to) do
    where(query, [sd], sd.collected_at <= ^date_to)
  end
  defp maybe_filter_by_date_range(query, date_from, date_to) do
    where(query, [sd], sd.collected_at >= ^date_from and sd.collected_at <= ^date_to)
  end

  defp normalize_api_data(api_data) do
    %{
      objective: api_data["objetive"],
      sale: api_data["sale"],
      percentual_sale: api_data["percentualSale"],
      discount: api_data["discount"],
      nfs: api_data["nfs"],
      mix: api_data["mix"],
      objective_today: api_data["objetiveToday"],
      sale_today: api_data["saleToday"],
      nfs_today: api_data["nfsToday"],
      devolution: api_data["devolution"],
      objective_hour: api_data["objetiveHour"],
      percentual_objective_hour: api_data["percentualObjetiveHour"],
      objective_total_hour: api_data["objetiveTotalHour"],
      percentual_objective_total_hour: api_data["percentualObjetiveTotalHour"],
      sale_supervisor: api_data["saleSupervisor"]
    }
  end
end
