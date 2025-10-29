defmodule App.Dashboard.DataStore do
  @moduledoc """
  GenServer responsável apenas por armazenar e gerenciar o estado dos dados do dashboard.
  Segue o padrão Single Responsibility Principle.
  """

  use GenServer

  @type state :: %{
    data: map() | nil,
    last_update: DateTime.t() | nil,
    api_status: :ok | :error | :loading | :initializing,
    api_error: String.t() | nil
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_data(timeout \\ 5_000) do
    GenServer.call(__MODULE__, :get_data, timeout)
  end

  def update_data(data) do
    GenServer.cast(__MODULE__, {:update_data, data})
  end

  def update_status(status, error \\ nil) do
    GenServer.cast(__MODULE__, {:update_status, status, error})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
    end

  @impl GenServer
  def init(_opts) do
    initial_state = %{
      data: nil,
      last_update: nil,
      api_status: :initializing,
      api_error: nil
    }

    {:ok, initial_state}
  end

  @impl GenServer
  def handle_call(:get_data, _from, %{data: nil, api_status: status} = state)
      when status in [:initializing, :loading] do
    {:reply, {:loading, nil}, state}
  end

  @impl GenServer
  def handle_call(:get_data, _from, %{data: data, api_status: :ok} = state)
      when not is_nil(data) do
    {:reply, {:ok, data}, state}
  end

  @impl GenServer
  def handle_call(:get_data, _from, state) do
    {:reply, {:error, state.api_error || "Dados não disponíveis"}, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status_info = %{
      api_status: state.api_status,
      last_update: state.last_update,
      has_data: not is_nil(state.data)
    }
    {:reply, status_info, state}
  end

  @impl GenServer
  def handle_cast({:update_data, data}, state) do
    new_state = %{
      state |
      data: data,
      last_update: DateTime.utc_now(),
      api_status: :ok,
      api_error: nil
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:update_status, status, error}, state) do
    new_state = %{
      state |
      api_status: status,
      api_error: error,
      last_update: DateTime.utc_now()
    }

    {:noreply, new_state}
  end
end
