defmodule App.Repo.Migrations.IncreaseTextFieldLength do
  use Ecto.Migration

  def change do
    # Aumentar o limite do campo text para 5000 caracteres
    alter table(:messages) do
      modify :text, :string, size: 5000
    end
  end
end
