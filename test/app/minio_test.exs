defmodule App.MinioTest do
  @moduledoc """
  Testes para o módulo de upload MinIO, incluindo funcionalidades expandidas
  para documentos (PDF, Word, Excel, PowerPoint).

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  use ExUnit.Case, async: true

  alias App.Minio

  @valid_image_path "/tmp/test_image.jpg"
  @valid_pdf_path "/tmp/test_document.pdf"
  @valid_docx_path "/tmp/test_document.docx"
  @valid_xlsx_path "/tmp/test_document.xlsx"
  @valid_pptx_path "/tmp/test_document.pptx"

  setup do
    # Criar arquivos temporários para testes
    File.write!(@valid_image_path, "fake image content")
    File.write!(@valid_pdf_path, "fake pdf content")
    File.write!(@valid_docx_path, "fake docx content")
    File.write!(@valid_xlsx_path, "fake xlsx content")
    File.write!(@valid_pptx_path, "fake pptx content")

    on_exit(fn ->
      File.rm(@valid_image_path)
      File.rm(@valid_pdf_path)
      File.rm(@valid_docx_path)
      File.rm(@valid_xlsx_path)
      File.rm(@valid_pptx_path)
    end)

    :ok
  end

  describe "upload_file/3 para documentos" do
    test "faz upload de arquivo PDF com sucesso" do
      filename = "test_document.pdf"

      assert {:ok, url} = Minio.upload_file(@valid_pdf_path, filename)
      assert String.contains?(url, filename)
      assert String.contains?(url, "localhost:9000")
    end

    test "faz upload de arquivo DOCX com sucesso" do
      filename = "test_document.docx"

      assert {:ok, url} = Minio.upload_file(@valid_docx_path, filename)
      assert String.contains?(url, filename)
    end

    test "faz upload de arquivo XLSX com sucesso" do
      filename = "test_document.xlsx"

      assert {:ok, url} = Minio.upload_file(@valid_xlsx_path, filename)
      assert String.contains?(url, filename)
    end

    test "faz upload de arquivo PPTX com sucesso" do
      filename = "test_document.pptx"

      assert {:ok, url} = Minio.upload_file(@valid_pptx_path, filename)
      assert String.contains?(url, filename)
    end

    test "rejeita arquivo com extensão não suportada" do
      filename = "test_virus.exe"

      assert {:error, {:unsupported_file_type, ".exe"}} =
        Minio.upload_file(@valid_pdf_path, filename)
    end
  end

  describe "supported_file_type?/1 para documentos" do
    test "aceita tipos de documentos PDF" do
      assert Minio.supported_file_type?("documento.pdf")
      assert Minio.supported_file_type?("ARQUIVO.PDF")
    end

    test "aceita tipos de documentos Word" do
      assert Minio.supported_file_type?("documento.doc")
      assert Minio.supported_file_type?("documento.docx")
    end

    test "aceita tipos de documentos Excel" do
      assert Minio.supported_file_type?("planilha.xls")
      assert Minio.supported_file_type?("planilha.xlsx")
    end

    test "aceita tipos de documentos PowerPoint" do
      assert Minio.supported_file_type?("apresentacao.ppt")
      assert Minio.supported_file_type?("apresentacao.pptx")
    end

    test "rejeita tipos não suportados" do
      refute Minio.supported_file_type?("arquivo.exe")
      refute Minio.supported_file_type?("arquivo.zip")
      refute Minio.supported_file_type?("arquivo.txt")
    end
  end

  describe "get_content_type/1 para documentos" do
    test "retorna content-type correto para PDF" do
      assert Minio.get_content_type("documento.pdf") == "application/pdf"
    end

    test "retorna content-type correto para Word" do
      assert Minio.get_content_type("documento.doc") == "application/msword"
      assert Minio.get_content_type("documento.docx") ==
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    end

    test "retorna content-type correto para Excel" do
      assert Minio.get_content_type("planilha.xls") == "application/vnd.ms-excel"
      assert Minio.get_content_type("planilha.xlsx") ==
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    end

    test "retorna content-type correto para PowerPoint" do
      assert Minio.get_content_type("apresentacao.ppt") == "application/vnd.ms-powerpoint"
      assert Minio.get_content_type("apresentacao.pptx") ==
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    end
  end

  describe "validação de tamanho para documentos" do
    test "aceita documentos dentro do limite de tamanho" do
      # Arquivo pequeno deve passar
      filename = "small_document.pdf"

      assert {:ok, url} = Minio.upload_file(@valid_pdf_path, filename)
      assert is_binary(url)
    end

    test "rejeita documentos muito grandes" do
      # Simular arquivo muito grande (mock do tamanho)
      large_content = String.duplicate("a", 50_000_000) # 50MB
      large_file_path = "/tmp/large_document.pdf"
      File.write!(large_file_path, large_content)

      filename = "large_document.pdf"

      assert {:error, {:file_too_large, _size, _max_size}} =
        Minio.upload_file(large_file_path, filename)

      File.rm(large_file_path)
    end
  end
end
