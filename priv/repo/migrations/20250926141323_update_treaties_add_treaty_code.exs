defmodule App.Repo.Migrations.UpdateTreatiesAddTreatyCode do
  use Ecto.Migration

  def change do
    # Alterar a tabela treaties para usar UUID como chave primária
    alter table(:treaties) do
      # Adicionar coluna treaty_code
      add :treaty_code, :string

      # Remover a chave primária string atual
      remove :id, :string
    end

    # Adicionar nova chave primária UUID
    alter table(:treaties, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    end

    # Criar índice único para treaty_code
    create unique_index(:treaties, [:treaty_code])
  end
end
