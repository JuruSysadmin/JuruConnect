defmodule App.Repo.Migrations.CreateGuardianTokens do
  use Ecto.Migration

  def change do
    create table(:guardian_tokens, primary_key: false) do
      add :jti, :string, primary_key: true
      add :aud, :string
      add :typ, :string
      add :iss, :string
      add :sub, :string
      add :exp, :bigint
      add :jwt, :text
      add :claims, :map

      timestamps()
    end

    create index(:guardian_tokens, [:sub])
    create index(:guardian_tokens, [:exp])
    create index(:guardian_tokens, [:typ])
    create unique_index(:guardian_tokens, [:jti, :aud])
  end
end
