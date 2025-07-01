defmodule App.LinkPreview do
  @moduledoc """
  Módulo para extração de previews de links com metadados Open Graph.

  Funcionalidades:
  - Extração de metadados Open Graph (og:title, og:description, og:image)
  - Detecção automática de URLs em texto de mensagens
  - Validação de URLs
  - Fallback para títulos HTML quando Open Graph não disponível
  - Timeout de segurança para requisições

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  require Logger

  @timeout 5000  # 5 segundos timeout
  @description_max_length 300
  @url_regex ~r/https?:\/\/[^\s]+/i

  @doc """
  Extrai preview de metadados de uma URL.

  ## Parâmetros
  - url: URL válida para extrair metadados

  ## Retorna
  {:ok, %{title: String.t(), description: String.t(), image: String.t(), url: String.t()}} | {:error, atom()}

  ## Exemplos

      iex> App.LinkPreview.extract_preview("https://github.com/elixir-lang/elixir")
      {:ok, %{title: "GitHub - elixir-lang/elixir", description: "...", image: "...", url: "..."}}
  """
  @spec extract_preview(String.t()) :: {:ok, map()} | {:error, atom()}
  def extract_preview(url) do
    with :ok <- validate_url(url),
         {:ok, html} <- fetch_html_safe(url),
         {:ok, metadata} <- parse_metadata(html, url) do
      {:ok, metadata}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unknown_error}
    end
  end

  @doc """
  Detecta URLs em um texto de mensagem.

  ## Parâmetros
  - text: Texto da mensagem para analisar

  ## Retorna
  Lista de URLs encontradas

  ## Exemplos

      iex> App.LinkPreview.detect_urls("Confira https://example.com")
      ["https://example.com"]
  """
  @spec detect_urls(String.t()) :: [String.t()]
  def detect_urls(text) when is_binary(text) do
    @url_regex
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.filter(&(validate_url(&1) == :ok))
    |> Enum.uniq()
  end

  def detect_urls(_), do: []

  @doc """
  Valida se uma URL é válida e suportada.

  ## Parâmetros
  - url: URL para validar

  ## Retorna
  :ok | {:error, atom()}
  """
  @spec validate_url(String.t()) :: :ok | {:error, atom()}
  def validate_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      is_nil(uri.scheme) or is_nil(uri.host) -> {:error, :invalid_url}
      uri.scheme not in ["http", "https"] -> {:error, :unsupported_protocol}
      String.trim(uri.host) == "" -> {:error, :invalid_url}
      String.contains?(uri.host, "..") -> {:error, :invalid_url}
      true -> :ok
    end
  end

  def validate_url(_), do: {:error, :invalid_url}

  @doc """
  Processa texto de mensagem e extrai preview do primeiro link encontrado.

  ## Parâmetros
  - message_text: Texto da mensagem

  ## Retorna
  {:ok, map() | nil} | {:error, atom()}
  """
  @spec process_message_for_links(String.t()) :: {:ok, map() | nil} | {:error, atom()}
  def process_message_for_links(message_text) when is_binary(message_text) do
    case detect_urls(message_text) do
      [] ->
        {:ok, nil}
      [first_url | _] ->
        case extract_preview(first_url) do
          {:ok, preview} ->
            link_data = %{
              preview_title: Map.get(preview, :title),
              preview_description: Map.get(preview, :description),
              preview_image: Map.get(preview, :image),
              preview_url: Map.get(preview, :url)
            }
            {:ok, link_data}
          {:error, _reason} ->
            {:ok, nil}
        end
    end
  end

  def process_message_for_links(_), do: {:ok, nil}

  # Funções privadas

  defp fetch_html_safe(url) do
    Logger.debug("Buscando HTML para: #{url}")

    try do
      task = Task.async(fn ->
        HTTPoison.get(url, [], timeout: @timeout, recv_timeout: @timeout)
      end)

      case Task.await(task, @timeout + 1000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body}
        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.warning("Status HTTP #{status} para #{url}")
          {:error, :http_error}
        {:error, %HTTPoison.Error{reason: :timeout}} ->
          {:error, :timeout}
        {:error, reason} ->
          Logger.warning("Erro ao buscar #{url}: #{inspect(reason)}")
          {:error, :http_error}
      end
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}
      error ->
        Logger.error("Erro inesperado ao buscar #{url}: #{inspect(error)}")
        {:error, :unknown_error}
    end
  end

  defp parse_metadata(html, url) do
    try do
      title = extract_og_tag(html, "og:title") || extract_html_title(html) || "Link"
      description = extract_og_tag(html, "og:description") || extract_meta_description(html)
      image = extract_og_tag(html, "og:image")

      # Limitar tamanho da descrição
      description = if description do
        String.slice(description, 0, @description_max_length)
      else
        nil
      end

      metadata = %{
        title: title,
        description: description,
        image: image,
        url: url
      }

      {:ok, metadata}
    rescue
      error ->
        Logger.error("Erro ao analisar HTML de #{url}: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  defp extract_og_tag(html, property) do
    regex = ~r/<meta[^>]*property\s*=\s*["']#{Regex.escape(property)}["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>/i

    case Regex.run(regex, html) do
      [_, content] -> String.trim(content)
      _ -> nil
    end
  end

  defp extract_html_title(html) do
    case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, html) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_meta_description(html) do
    regex = ~r/<meta[^>]*name\s*=\s*["']description["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>/i

    case Regex.run(regex, html) do
      [_, content] -> String.trim(content)
      _ -> nil
    end
  end
end
