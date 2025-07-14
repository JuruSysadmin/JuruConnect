defmodule App.Repo do
  @moduledoc """
  Repositório Ecto principal da aplicação JuruConnect.

  Responsável por todas as operações de persistência, consulta e transação com o banco de dados PostgreSQL.

  Este módulo é utilizado por todos os contextos para acessar e manipular dados de forma segura e eficiente.
  """
  use Ecto.Repo,
    otp_app: :app,
    adapter: Ecto.Adapters.Postgres
end
