defmodule App.Services.GeminiService do
  @moduledoc """
  Serviço para integração com a API do Gemini Google.

  Permite enviar perguntas e receber respostas através de comandos no chat.
  """

  @base_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
  @api_key Application.compile_env(:app, __MODULE__)[:api_key] || System.get_env("GEMINI_API_KEY")

  @doc """
  Gera uma resposta do Gemini para uma pergunta do usuário.

  ## Exemplos

      iex> App.Services.GeminiService.generate_response("Como funciona a IA?")
      {:ok, "A inteligência artificial (IA) funciona através de..."}

      iex> App.Services.GeminiService.generate_response("", "user_question")
      {:error, "Pergunta não pode estar vazia"}
  """
  def generate_response(question, treaty_id \\ nil) when is_binary(question) do
    trimmed_question = String.trim(question)

    cond do
      trimmed_question == "" ->
        {:error, "Pergunta não pode estar vazia"}

      String.length(trimmed_question) > 1000 ->
        {:error, "Pergunta muito longa. Limite: 1000 caracteres"}

      true ->
        context = if treaty_id, do: determine_context(treaty_id), else: "geral"
        call_gemini_api(trimmed_question, context)
    end
  end

  @doc """
  Verifica se uma mensagem é um comando válido para IA.

  ## Exemplos

      iex> App.Services.GeminiService.is_ai_command?("/ai Como funciona a IA?")
      true

      iex> App.Services.GeminiService.is_ai_command?("/pergunta Qual é a capital do Brasil?")
      true

      iex> App.Services.GeminiService.is_ai_command?("Olá pessoal")
      false
  """
  def is_ai_command?(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.starts_with?(["/ai ", "/pergunta "])
  end

  @doc """
  Extrai a pergunta do comando da IA.

  ## Exemplo

      iex> App.Services.GeminiService.extract_question("/ai Como funciona a IA?")
      {:ok, "Como funciona a IA?", "ai"}

      iex> App.Services.GeminiService.extract_question("/pergunta Qual é a capital?")
      {:ok, "Qual é a capital?", "pergunta"}

      iex> App.Services.GeminiService.extract_question("Olá pessoal")
      {:error, "Não é um comando de IA"}
  """
  def extract_question(message) when is_binary(message) do
    message = String.trim(message)

    cond do
      String.starts_with?(message, "/ai ") ->
        question = message |> String.replace_prefix("/ai ", "") |> String.trim()
        {:ok, question, "ai"}

      String.starts_with?(message, "/pergunta ") ->
        question = message |> String.replace_prefix("/pergunta ", "") |> String.trim()
        {:ok, question, "pergunta"}

      true ->
        {:error, "Não é um comando de IA"}
    end
  end

  # Funções privadas

  defp call_gemini_api(question, context) do
    payload = build_request_payload(question, context)

    case make_http_request(payload) do
      {:ok, response} ->
        parse_gemini_response(response)

      {:error, error} ->
        {:error, "Erro na conexão com Gemini: #{error}"}
    end
  end

  defp build_request_payload(question, context) do
    system_prompt = get_system_prompt(context)
    full_prompt = "#{system_prompt}\n\nPergunta: #{question}"

    %{
      contents: [
        %{
          parts: [
            %{
              text: full_prompt
            }
          ]
        }
      ]
    }
  end

  defp determine_context(treaty_id) when is_binary(treaty_id) do
    # Extrair número do pedido se possível (assumindo que treaty_code pode conter o número do pedido)
    case extract_pedido_number(treaty_id) do
      {:ok, pedido_number} ->
        case fetch_pedido_data(pedido_number) do
          {:ok, pedido_data} ->
            "#{pedido_data} - ID da tratativa: #{treaty_id}"
          {:error, _reason} ->
            "Tratativa #{treaty_id} - Pedido #{pedido_number} não encontrado na API."
        end
      {:error, _reason} ->
        "Tratativa #{treaty_id} - Não foi possível identificar o número do pedido."
    end
  end

  # Extrai número do pedido do treaty_id ou código
  defp extract_pedido_number(treaty_id) do
    # Tentar extrair número do pedido diretamente do treaty_id
    case Regex.run(~r/\d{9}/, treaty_id) do
      [pedido_number] ->
        {:ok, pedido_number}
      nil ->
        # Tentar buscar o treaty_code para extrair número
        case App.Treaties.get_treaty(treaty_id) do
          {:ok, treaty} ->
            case Regex.run(~r/\d{9}/, treaty.treaty_code) do
              [pedido_number] -> {:ok, pedido_number}
              nil -> {:error, "Número do pedido não encontrado"}
            end
          {:error, _} -> {:error, "Tratativa não encontrada"}
        end
    end
  end

  # Consulta a API de pedidos
  defp fetch_pedido_data(pedido_number) do
    api_url = "http://10.1.119.91:8066/api/v1/orders/leadtime/#{pedido_number}"

    case HTTPoison.get(api_url, [
      {"Content-Type", "application/json"}
    ], timeout: 5000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"success" => true, "data" => data}} when is_list(data) and length(data) > 0 ->
            formatted_data = format_pedido_data(data)
            {:ok, formatted_data}
          {:ok, %{"success" => false}} ->
            {:error, "API retornou success: false"}
          {:ok, %{"data" => []}} ->
            {:error, "Não há etapas registradas para este pedido"}
          {:error, decode_error} ->
            {:error, "Erro ao decodificar JSON: #{inspect(decode_error)}"}
        end
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Pedido #{pedido_number} não encontrado"}
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "API retornou status #{status_code}"}
      {:error, reason} ->
        {:error, "Erro de conexão com API: #{inspect(reason)}"}
    end
  end

  # Formata os dados do pedido para o contexto da IA
  defp format_pedido_data(data) when is_list(data) do
    current_etapa = get_current_etapa(data)
    etapas_percorridas = format_etapas_percorridas(data)

    """
    DADOS DO PEDIDO #{get_pedido_number(data)}:
    Etapa atual: #{current_etapa}

    Etapas percorridas:
    #{etapas_percorridas}

    IMPORTANTE: Utilize estas informações para responder perguntas sobre:
    - Qual etapa o pedido está atualmente
    - Histórico de etapas percorridas
    - Datas e funcionários responsáveis por cada etapa
    - Tempo decorrido em cada etapa
    Responda sempre em português brasileiro de forma clara e objetiva.
    """
  end

  defp get_current_etapa(data) when is_list(data) do
    case List.last(data) do
      nil -> "Não identificada"
      %{"descricaoEtapa" => etapa} -> etapa
    end
  end

  defp get_pedido_number([first | _]) when is_map(first) do
    case Map.get(first, "numeroPedido") do
      nil -> "N/A"
      numero when is_binary(numero) or is_integer(numero) -> "#{numero}"
    end
  end
  defp get_pedido_number(_), do: "N/A"

  defp format_etapas_percorridas(data) when is_list(data) do
    data
    |> Enum.with_index(1)
    |> Enum.map(fn {etapa, index} ->
      data_str = parse_datetime(etapa["data"])
      funcionario = etapa["nomeFuncionario"] || "Não informado"
      numero_etapa = etapa["etapa"] || index
      descricao = etapa["descricaoEtapa"] || "Etapa #{numero_etapa}"

      "  #{numero_etapa}. #{descricao} - #{data_str} (#{funcionario})"
    end)
    |> Enum.join("\n")
  end

  # Parse simples de datetime para formato legível
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} ->
        datetime
        |> DateTime.shift_zone!("America/Sao_Paulo")
        |> DateTime.to_naive()
        |> NaiveDateTime.to_string()
        |> String.slice(0, 16)  # Remove milissegundos
      {:error, _} ->
        datetime_string
    end
  end
  defp parse_datetime(other), do: "#{inspect(other)}"

  defp get_system_prompt(context) do
    base_prompt = """
    Você é um assistente IA integrado ao sistema de chat JuruConnect para consulta de pedidos.

    Responda de forma breve, útil e em português brasileiro.
    Seja educado, profissional e focado nas perguntas dos usuários.

    Sua especialidade é responder perguntas sobre:
    - Status atual de pedidos
    - Etapas percorridas pelo pedido
    - Prazos e datas importantes
    - Funcionários responsáveis pelas etapas
    - Tempo decorrido em cada etapa
    """

    # Se context é uma string longa contendo dados do pedido
    if String.contains?(context, "DADOS DO PEDIDO") do
      base_prompt <> """

      #{context}

      BASEADO NOS DADOS ACIMA, responda de forma específica e detalhada.
      """
    else
      base_prompt <> """

      Contexto geral: Responda perguntas de forma educada e útil.
      Se precisar de informações específicas de pedido, peça para o usuário fornecer o número do pedido.
      """
    end
  end

  defp make_http_request(payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"X-goog-api-key", @api_key}
    ]

    case HTTPoison.post(@base_url, Jason.encode!(payload), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        error_msg = parse_gemini_error(body)
        {:error, "Erro #{status_code}: #{error_msg}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, inspect(reason)}
    end
  end

  defp parse_gemini_response(response) do
    case response do
      %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}}]} ->
        cleaned_text = String.trim(text)

        if String.length(cleaned_text) > 1500 do
          # Limitar resposta muito longa
          limited_text = String.slice(cleaned_text, 0, 1500) <> "\\n\\n*[Resposta truncada devido ao limite de caracteres]*"
          {:ok, limited_text}
        else
          {:ok, cleaned_text}
        end

      %{"error" => error_info} ->
        error_message = Map.get(error_info, "message", "Erro desconhecido")
        {:error, "Gemini API: #{error_message}"}

      _ ->
        {:error, "Resposta inválida do Gemini"}
    end
  end

  defp parse_gemini_error(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error_info}} ->
        Map.get(error_info, "message", "Erro da API")

      _ ->
        "Resposta de erro não reconhecida"
    end
  end
end
