defmodule JuruConnect.Api.SupervisorClient do
  @moduledoc """
  Cliente HTTP para buscar dados de supervisores da API.

  Este módulo fornece uma interface simples para coletar dados da API
  e salvá-los no banco de dados, podendo ser usado manualmente ou
  via scheduler.
  """

  require Logger
  alias JuruConnect.Sales

  @default_timeout 30_000
  @default_headers [{"Content-Type", "application/json"}]

  @doc """
  Busca e salva dados de supervisores da API.

  ## Exemplos

      iex> fetch_and_save("https://api.exemplo.com/supervisores")
      {:ok, %SupervisorData{}}

      iex> fetch_and_save("https://api-invalida.com")
      {:error, {:http_request_error, :nxdomain}}
  """
  @spec fetch_and_save(String.t(), keyword()) ::
    {:ok, JuruConnect.Schemas.SupervisorData.t()} | {:error, term()}
  def fetch_and_save(api_url, opts \\ []) do
    headers = Keyword.get(opts, :headers, @default_headers)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Logger.info("Iniciando coleta de dados de supervisores", %{
      api_url: api_url,
      module: __MODULE__
    })

    with {:ok, data} <- fetch_data(api_url, headers, timeout),
         {:ok, supervisor_data} <- Sales.create_supervisor_data_from_api(data) do

      Logger.info("Dados salvos com sucesso", %{
        id: supervisor_data.id,
        collected_at: supervisor_data.collected_at,
        sellers_count: length(supervisor_data.sale_supervisor)
      })

      {:ok, supervisor_data}
    else
      {:error, reason} = error ->
        Logger.error("Erro na coleta de dados", %{
          reason: reason,
          api_url: api_url,
          module: __MODULE__
        })
        error
    end
  end

  @doc """
  Busca dados da API (sem salvar).

  ## Exemplos

      iex> fetch_data("https://api.exemplo.com/supervisores")
      {:ok, %{"objetive" => 100000, "sale" => 85000, ...}}
  """
  @spec fetch_data(String.t(), list(), integer()) :: {:ok, map()} | {:error, term()}
  def fetch_data(api_url, headers \\ @default_headers, timeout \\ @default_timeout) do
    case make_request(api_url, headers, timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        decode_response(body)

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %{reason: reason}} ->
        {:error, {:http_request_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executa coleta periódica usando Process.send_after.

  ## Exemplos

      # Coleta a cada 2 horas (7200 segundos)
      start_periodic_sync("https://api.exemplo.com/supervisores", 7200)
  """
  @spec start_periodic_sync(String.t(), integer(), keyword()) :: :ok
  def start_periodic_sync(api_url, interval_seconds, opts \\ []) do
    pid = spawn(fn -> periodic_loop(api_url, interval_seconds, opts) end)
    Process.register(pid, __MODULE__)

    Logger.info("Sync periódico iniciado", %{
      api_url: api_url,
      interval_seconds: interval_seconds,
      pid: pid
    })

    :ok
  end

  @doc """
  Para a coleta periódica.
  """
  @spec stop_periodic_sync() :: :ok
  def stop_periodic_sync do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid ->
        Process.exit(pid, :normal)
        :ok
    end
  end

  # Private functions

  defp make_request(api_url, headers, timeout) do
    # Se HTTPoison estiver disponível, usa ele
    if Code.ensure_loaded?(HTTPoison) do
      HTTPoison.get(api_url, headers, recv_timeout: timeout)
    else
      # Fallback usando :httpc (built-in no Erlang)
      case :httpc.request(:get, {String.to_charlist(api_url), headers},
                         [{:timeout, timeout}], []) do
        {:ok, {{_, 200, _}, _headers, body}} ->
          {:ok, %{status_code: 200, body: List.to_string(body)}}
        {:ok, {{_, status_code, _}, _headers, body}} ->
          {:ok, %{status_code: status_code, body: List.to_string(body)}}
        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    end
  end

  defp decode_response(body) do
    cond do
      Code.ensure_loaded?(Jason) ->
        Jason.decode(body)
      Code.ensure_loaded?(Poison) ->
        Poison.decode(body)
      true ->
        {:error, :no_json_library}
    end
  end

  defp periodic_loop(api_url, interval_seconds, opts) do
    fetch_and_save(api_url, opts)

    # Agenda próxima execução
    Process.sleep(interval_seconds * 1000)
    periodic_loop(api_url, interval_seconds, opts)
  end
end
