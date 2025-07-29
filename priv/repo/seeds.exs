# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     App.Repo.insert!(%App.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias App.Repo
alias App.Stores.Store
alias App.Accounts.User

# Criar loja padrão
store = case Repo.get_by(Store, name: "Loja Padrão") do
  nil ->
    %Store{
      name: "Loja Padrão",
      location: "Localização Padrão"
    }
    |> Repo.insert!()

  existing_store -> existing_store
end

users_data = [
  %{
    username: "joao",
    name: "João Silva",
    password: "123456",
    role: "clerk",
    store_id: store.id
  },
  %{
    username: "maria",
    name: "Maria Santos",
    password: "123456",
    role: "manager",
    store_id: store.id
  },
  %{
    username: "admin",
    name: "Administrador",
    password: "123456",
    role: "admin",
    store_id: store.id
  },
  %{
    username: "joelson",
    name: "Joelson",
    password: "123456",
    role: "manager",
    store_id: store.id
  },
  %{
    username: "beatriz",
    name: "Beatriz",
    password: "123456",
    role: "clerk",
    store_id: store.id
  }
]

Enum.each(users_data, fn user_data ->
  case Repo.get_by(User, username: user_data.username) do
    nil ->
      %User{}
      |> User.changeset(user_data)
      |> Repo.insert!()
      |> then(fn user ->
        IO.puts("Usuário criado: #{user.username} (#{user.name})")
      end)

    _existing_user ->
      IO.puts("Usuário já existe: #{user_data.username}")
  end
end)

IO.puts("Seeds executados com sucesso!")
