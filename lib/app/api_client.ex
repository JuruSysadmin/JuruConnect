defmodule App.ApiClient do
  @moduledoc """
  Cliente para consumir APIs externas
  """

  alias HTTPoison.Response
  alias HTTPoison.Error

  @base_url "http://10.1.1.212/api/v1"

  @doc """
  Busca dados resumidos do dashboard
  """
  def fetch_dashboard_summary do
    url = "#{@base_url}/dashboard/sale"
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            # Extrai apenas os campos desejados
            summary = %{
              "sale" => Map.get(data, "sale", 0.0),
              "cost" => Map.get(data, "cost", 0.0),
              "devolution" => Map.get(data, "devolution", 0.0),
              "objetivo" => Map.get(data, "objetivo", 0.0),
              "profit" => Map.get(data, "profit", 0.0),
              "percentual" => Map.get(data, "percentual", 0.0),
              "nfs" => Map.get(data, "nfs", 0)
            }
            {:ok, summary}
          {:error, error} -> {:error, "Erro ao decodificar JSON: #{inspect(error)}"}
        end
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Erro de conexão: #{inspect(reason)}"}
    end
  end
end
