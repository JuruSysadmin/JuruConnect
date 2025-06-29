defmodule App.Repo.Migrations.ChangeIpAddressToStringInSecurityEvents do
  use Ecto.Migration

  def up do
    # Alterar o tipo da coluna ip_address de inet para string
    alter table(:security_events) do
      modify :ip_address, :string
    end
  end

  def down do
    # Reverter para inet (cuidado: pode falhar se houver dados inválidos)
    alter table(:security_events) do
      modify :ip_address, :inet
    end
  end
end
