defmodule App.Repo.Migrations.AddTagsToMessages do
  @moduledoc """
  Adiciona suporte a tags nas mensagens do chat.
  """
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :tags, {:array, :string}, default: [], null: false
    end

    # Índice GIN é otimizado para buscas em arrays no PostgreSQL
    create index(:messages, [:tags], using: :gin)
  end
end
