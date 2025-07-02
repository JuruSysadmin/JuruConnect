defmodule App.Repo.Migrations.AddTipoToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :tipo, :string, default: "mensagem"
    end
  end
end
