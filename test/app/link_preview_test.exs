defmodule App.LinkPreviewTest do
  @moduledoc """
  Testes para o módulo de extração de preview de links.

  Testa funcionalidades de:
  - Extração de metadados Open Graph (og:title, og:description, og:image)
  - Detecção automática de URLs em texto
  - Validação de URLs
  - Fallback para títulos HTML quando Open Graph não disponível

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  use ExUnit.Case, async: true

  alias App.LinkPreview

  @valid_url "https://example.com"
  @url_with_og_tags "https://github.com/elixir-lang/elixir"
  @url_without_og_tags "https://httpbin.org/html"
  @invalid_url "not-a-url"
  @malformed_url "http://.com"

  describe "extract_preview/1" do
    test "extrai metadados Open Graph de URL válida" do
      assert {:ok, preview} = LinkPreview.extract_preview(@url_with_og_tags)

      assert Map.has_key?(preview, :title)
      assert Map.has_key?(preview, :description)
      assert Map.has_key?(preview, :image)
      assert Map.has_key?(preview, :url)

      assert preview.url == @url_with_og_tags
      assert is_binary(preview.title)
    end

    test "retorna erro para URL inválida" do
      assert {:error, :invalid_url} = LinkPreview.extract_preview(@invalid_url)
    end

    test "retorna erro para URL malformada" do
      assert {:error, :invalid_url} = LinkPreview.extract_preview(@malformed_url)
    end

    test "usa fallback para título HTML quando Open Graph não disponível" do
      assert {:ok, preview} = LinkPreview.extract_preview(@url_without_og_tags)

      assert preview.url == @url_without_og_tags
      # Deve ter pelo menos título, mesmo sem Open Graph
      assert is_binary(preview.title) and String.length(preview.title) > 0
    end

    test "limita tamanho da descrição extraída" do
      # Assumindo que implementaremos limite de 300 caracteres
      assert {:ok, preview} = LinkPreview.extract_preview(@url_with_og_tags)

      if preview.description do
        assert String.length(preview.description) <= 300
      end
    end
  end

  describe "detect_urls/1" do
    test "detecta URLs HTTP em texto" do
      text = "Confira este link http://example.com para mais informações"

      assert urls = LinkPreview.detect_urls(text)
      assert "http://example.com" in urls
    end

    test "detecta URLs HTTPS em texto" do
      text = "Site seguro: https://secure-example.com/path"

      assert urls = LinkPreview.detect_urls(text)
      assert "https://secure-example.com/path" in urls
    end

    test "detecta múltiplas URLs em texto" do
      text = "Links: https://site1.com e http://site2.com/page"

      assert urls = LinkPreview.detect_urls(text)
      assert length(urls) == 2
      assert "https://site1.com" in urls
      assert "http://site2.com/page" in urls
    end

    test "retorna lista vazia para texto sem URLs" do
      text = "Este texto não contém links válidos"

      assert LinkPreview.detect_urls(text) == []
    end

    test "ignora URLs malformadas" do
      text = "Link malformado: http:// e outro: https://.com"

      assert LinkPreview.detect_urls(text) == []
    end
  end

  describe "validate_url/1" do
    test "valida URLs HTTP corretas" do
      assert LinkPreview.validate_url("http://example.com") == :ok
      assert LinkPreview.validate_url("http://sub.example.com/path") == :ok
    end

    test "valida URLs HTTPS corretas" do
      assert LinkPreview.validate_url("https://example.com") == :ok
      assert LinkPreview.validate_url("https://example.com:8080/path?query=1") == :ok
    end

    test "rejeita URLs malformadas" do
      assert LinkPreview.validate_url("not-a-url") == {:error, :invalid_url}
      assert LinkPreview.validate_url("http://") == {:error, :invalid_url}
      assert LinkPreview.validate_url("https://.com") == {:error, :invalid_url}
    end

    test "rejeita protocolos não suportados" do
      assert LinkPreview.validate_url("ftp://example.com") == {:error, :unsupported_protocol}
      assert LinkPreview.validate_url("file:///path") == {:error, :unsupported_protocol}
    end
  end

  describe "process_message_for_links/1" do
    test "processa mensagem e extrai preview do primeiro link" do
      message_text = "Olha este artigo interessante: https://example.com/article"

      assert {:ok, link_data} = LinkPreview.process_message_for_links(message_text)

      assert Map.has_key?(link_data, :preview_title)
      assert Map.has_key?(link_data, :preview_description)
      assert Map.has_key?(link_data, :preview_image)
      assert Map.has_key?(link_data, :preview_url)

      assert link_data.preview_url == "https://example.com/article"
    end

    test "retorna nil para mensagem sem links" do
      message_text = "Mensagem normal sem links"

      assert LinkPreview.process_message_for_links(message_text) == {:ok, nil}
    end

    test "processa apenas o primeiro link quando há múltiplos" do
      message_text = "Links: https://site1.com e https://site2.com"

      assert {:ok, link_data} = LinkPreview.process_message_for_links(message_text)
      assert link_data.preview_url == "https://site1.com"
    end
  end

  describe "safe_extract/1 com timeout" do
    test "aplica timeout para requisições lentas" do
      # URL que pode demorar para responder
      slow_url = "https://httpbin.org/delay/10"

      # Deve retornar erro de timeout em menos de 5 segundos
      start_time = System.monotonic_time(:millisecond)
      result = LinkPreview.extract_preview(slow_url)
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time

      # Deve falhar por timeout
      assert {:error, :timeout} = result
      # E deve ser mais rápido que 10 segundos
      assert elapsed < 8000
    end
  end
end
