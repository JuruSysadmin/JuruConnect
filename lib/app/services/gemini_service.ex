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
  def generate_response(question, context \\ "geral") when is_binary(question) do
    trimmed_question = String.trim(question)

    cond do
      trimmed_question == "" ->
        {:error, "Pergunta não pode estar vazia"}

      String.length(trimmed_question) > 1000 ->
        {:error, "Pergunta muito longa. Limite: 1000 caracteres"}

      true ->
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

  defp get_system_prompt(context) do
    base_prompt = """
    Você é um assistente IA integrado ao sistema de chat JuruConnect.

    Responda de forma breve, útil e em português brasileiro.

    Seja educado, profissional e focado nas perguntas dos usuários.
    """

    case context do
      "suporte" ->
        base_prompt <> """

        Contexto: Esta é uma sala de suporte técnico. Ajude com:
        - Dúvidas sobre produtos e serviços
        - Problemas técnicos
        - Orientações de uso
        """

      "vendas" ->
        base_prompt <> """

        Contexto: Esta é uma sala de vendas. Ajude com:
        - Informações sobre produtos
        - Processos de compra
        - Orientações comerciais
        """

      _ ->
        base_prompt <>
        """

        Contexto geral: Responda perguntas de forma educada e útil.
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
