defmodule App.DashboardDataServer do
  @moduledoc """
  GenServer para buscar e armazenar dados do dashboard em tempo real.

  CORREÇÕES:
  - Fetch inicial imediato (não espera 30s)
  - Timeout configurável no GenServer.call
  - Estado consistente (api_status e fetching)
  - Melhor tratamento de erros
  """

  use GenServer
  alias App.ApiClient

  @fetch_interval 30_000
  @call_timeout 10_000

  # API Pública
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_data(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @call_timeout)

    try do
      GenServer.call(__MODULE__, {:get_data, false}, timeout)
    catch
      :exit, {:timeout, _} ->
        {:timeout, "Timeout ao buscar dados (#{timeout}ms)"}
    end
  end

  def get_data_sync(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @call_timeout)
    max_attempts = Keyword.get(opts, :max_attempts, 10)

    Enum.reduce_while(1..max_attempts, {:loading, nil}, fn attempt, _acc ->
      case get_data(timeout: timeout) do
        {:ok, data} ->
          {:halt, {:ok, data}}

        {:loading, nil} when attempt < max_attempts ->
          Process.sleep(1000)
          {:cont, {:loading, nil}}

        {:loading, nil} ->
          {:halt, {:error, "Dados não carregaram após #{max_attempts} tentativas"}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        {:timeout, reason} ->
          {:halt, {:timeout, reason}}
      end
    end)
  end

  def force_refresh do
    GenServer.cast(__MODULE__, :force_fetch)
  end

  def status do
    GenServer.call(__MODULE__, :status, 5_000)
  end

  # Callbacks do GenServer

  def init(_) do

    # Estado inicial mais preciso
    initial_state = %{
      data: nil,
      api_status: :initializing,
      api_error: nil,
      last_update: nil,
      fetching: false,
      fetch_count: 0
    }

    # Disparo imediato de fetch
    send(self(), :fetch)

    {:ok, initial_state}
  end

  # Função para verificar se já existe fetch pendente
  defp fetch_already_pending? do
    case Process.info(self(), :messages) do
      {:messages, messages} ->
        Enum.any?(messages, &match?(:fetch, &1))
      _ ->
        false
    end
  end

  # Fetch inicial e periódico (unificado)
  def handle_info(:fetch, %{fetching: true} = state) do
    # Se já está fazendo fetch, ignora e reagenda
    unless fetch_already_pending?() do
      schedule_next_fetch()
    end
    {:noreply, state}
  end

  def handle_info(:fetch, state) do
    new_state = %{state | fetching: true, api_status: :loading}

    case fetch_dashboard_data() do
      {:ok, data} ->
        success_state = %{
          new_state
          | data: data,
            api_status: :ok,
            api_error: nil,
            last_update: DateTime.utc_now(),
            fetching: false,
            fetch_count: state.fetch_count + 1
        }

        Phoenix.PubSub.broadcast(App.PubSub, "dashboard:updated", {:dashboard_updated, data})

        schedule_next_fetch_if_needed()
        {:noreply, success_state}

      {:error, reason} ->
        error_state = %{
          new_state
          | api_status: :error,
            api_error: reason,
            last_update: DateTime.utc_now(),
            fetching: false
        }

        schedule_error_retry(state.fetch_count)
        {:noreply, error_state}
    end
  end

  # Calls síncronos - retorna tuplas mais claras
  def handle_call({:get_data, _wait_for_data}, _from, %{data: nil, api_status: status} = state)
      when status in [:initializing, :loading] do
    {:reply, {:loading, nil}, state}
  end

  def handle_call({:get_data, _wait_for_data}, _from, %{data: data, api_status: :ok} = state)
      when not is_nil(data) do
    {:reply, {:ok, data}, state}
  end

  def handle_call({:get_data, _wait_for_data}, _from, state) do
    # Para casos de erro ou estados inesperados
    {:reply, {:error, state.api_error || "Dados não disponíveis"}, state}
  end

  def handle_call(:status, _from, state) do
    status_info = %{
      api_status: state.api_status,
      fetching: state.fetching,
      last_update: state.last_update,
      fetch_count: state.fetch_count,
      has_data: not is_nil(state.data)
    }

    {:reply, status_info, state}
  end

  # Casts assíncronos
  def handle_cast(:force_fetch, state) do
    if not state.fetching and not fetch_already_pending?() do
      send(self(), :fetch)
    end

    {:noreply, state}
  end

  # Funções privadas

  defp schedule_next_fetch do
    # Evita múltiplos timers usando a função centralizada
    unless fetch_already_pending?() do
      Process.send_after(self(), :fetch, @fetch_interval)
    end
  end

  defp schedule_next_fetch_if_needed do
    unless fetch_already_pending?() do
      schedule_next_fetch()
    end
  end

  defp schedule_error_retry(fetch_count) do
    unless fetch_already_pending?() do
      if fetch_count == 0 do
        # Primeiro fetch - tenta novamente rapidamente
        Process.send_after(self(), :fetch, 5_000)
      else
        # Fetches subsequentes - agenda normalmente
        schedule_next_fetch()
      end
    end
  end

  defp fetch_dashboard_data do
    with {:ok, sale_data} <- ApiClient.fetch_dashboard_summary(),
         {:ok, company_result} <- ApiClient.fetch_companies_data() do
      companies = Map.get(company_result, :companies, [])
      percentual_sale = Map.get(company_result, :percentualSale, 0.0)

      merged_data =
        Map.merge(sale_data, %{
          "companies" => companies,
          "percentualSale" => percentual_sale
        })

      # Nova verificação de celebrações REAL baseada nos dados da API
      App.CelebrationManager.process_api_data(merged_data)



      {:ok, merged_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end


end
