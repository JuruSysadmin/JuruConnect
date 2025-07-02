defmodule App.Repo.Migrations.AddDocumentAndLinkPreviewFieldsToMessages do
  @moduledoc """
  Adiciona campos para upload de documentos e preview de links às mensagens.

  Campos adicionados:
  - document_url: URL do documento no MinIO
  - document_name: Nome original do documento
  - document_size: Tamanho do documento em bytes
  - link_preview_title: Título extraído do link
  - link_preview_description: Descrição extraída do link
  - link_preview_image: URL da imagem do preview
  - link_preview_url: URL original do link
  """

  use Ecto.Migration

  def change do
    alter table(:messages) do
      # Campos para documentos
      add :document_url, :string
      add :document_name, :string
      add :document_size, :integer

      # Campos para preview de links
      add :link_preview_title, :string
      add :link_preview_description, :text
      add :link_preview_image, :string
      add :link_preview_url, :string
    end

    # Índices para otimizar consultas
    create index(:messages, [:document_url])
    create index(:messages, [:link_preview_url])
  end
end
