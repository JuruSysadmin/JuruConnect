defmodule JuruConnect.Workers.SupervisorDataWorker do
  @moduledoc """
  Worker do Oban responsável por coletar dados de supervisores da API.

  Este worker executa periodicamente para manter os dados atualizados,
  fazendo requisições HTTP para a API e salvando no banco de dados.
  """

  use Oban.Worker,
    queue: :api_sync,
    max_attempts: 3,
    tags: ["api", "supervisor_data"]

  require Logger
  alias JuruConnect.Sales

  @doc """
  Executa a coleta de dados da API.

  ## Argumentos esperados:
  - `api_url`: URL da API para buscar dados
  - `headers`: Headers HTTP opcionais (default: [])
  - `timeout`: Timeout em millisegundos (default: 30000)
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    api_url = Map.get(args, "api_url")
    headers = Map.get(args, "headers", [])
    timeout = Map.get(args, "timeout", 30_000)

    Logger.info("Iniciando coleta de dados de supervisores", %{
      api_url: api_url,
      worker: __MODULE__
    })

    case fetch_supervisor_data(api_url, headers, timeout) do
      {:ok, data} ->
        case Sales.create_supervisor_data_from_api(data) do
          {:ok, supervisor_data} ->
            Logger.info("Dados de supervisores salvos com sucesso", %{
              id: supervisor_data.id,
              collected_at: supervisor_data.collected_at,
              sellers_count: length(supervisor_data.sale_supervisor)
            })
            :ok

          {:error, changeset} ->
            Logger.error("Erro ao salvar dados de supervisores", %{
              errors: changeset.errors,
              worker: __MODULE__
            })
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Erro ao buscar dados da API", %{
          reason: reason,
          api_url: api_url,
          worker: __MODULE__
        })
        {:error, reason}
    end
  end

  @doc """
  Agenda a próxima execução do worker.
  """
  @spec schedule_next(map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_next(args, opts \\ []) do
    args
    |> new(opts)
    |> Oban.insert()
  end

  defp fetch_supervisor_data(api_url, headers, timeout) do
    case HTTPoison.get(api_url, headers, recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, decode_error} -> {:error, {:json_decode_error, decode_error}}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_request_error, reason}}
    end
  end
end

# CÓDIGO COMENTADO DO WORKER REAL:
#
# if Code.ensure_loaded?(Oban.Worker) do
#   defmodule JuruConnect.Workers.SupervisorDataWorker do
#     use Oban.Worker,
#       queue: :api_sync,
#       max_attempts: 3,
#       tags: ["api", "supervisor_data"]
#
#     require Logger
#     alias JuruConnect.Sales
#
#     @impl Oban.Worker
#     def perform(%Oban.Job{args: args}) do
#       api_url = Map.get(args, "api_url")
#       headers = Map.get(args, "headers", [])
#       timeout = Map.get(args, "timeout", 30_000)
#
#       Logger.info("Iniciando coleta de dados de supervisores", %{
#         api_url: api_url,
#         worker: __MODULE__
#       })
#
#       case fetch_supervisor_data(api_url, headers, timeout) do
#         {:ok, data} ->
#           case Sales.create_supervisor_data_from_api(data) do
#             {:ok, supervisor_data} ->
#               Logger.info("Dados de supervisores salvos com sucesso", %{
#                 id: supervisor_data.id,
#                 collected_at: supervisor_data.collected_at,
#                 sellers_count: length(supervisor_data.sale_supervisor)
#               })
#               :ok
#
#             {:error, changeset} ->
#               Logger.error("Erro ao salvar dados de supervisores", %{
#                 errors: changeset.errors,
#                 worker: __MODULE__
#               })
#               {:error, changeset}
#           end
#
#         {:error, reason} ->
#           Logger.error("Erro ao buscar dados da API", %{
#             reason: reason,
#             api_url: api_url,
#             worker: __MODULE__
#           })
#           {:error, reason}
#       end
#     end
#
#     def schedule_next(args, opts \\ []) do
#       args
#       |> new(opts)
#       |> Oban.insert()
#     end
#
#     defp fetch_supervisor_data(api_url, headers, timeout) do
#       case HTTPoison.get(api_url, headers, recv_timeout: timeout) do
#         {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
#           case Jason.decode(body) do
#             {:ok, data} -> {:ok, data}
#             {:error, decode_error} -> {:error, {:json_decode_error, decode_error}}
#           end
#
#         {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
#           {:error, {:http_error, status_code, body}}
#
#         {:error, %HTTPoison.Error{reason: reason}} ->
#           {:error, {:http_request_error, reason}}
#       end
#     end
#   end
# end
