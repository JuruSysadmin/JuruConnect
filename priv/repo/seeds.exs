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
alias App.Tags.Tag

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

# Buscar o admin para ser o criador das tags
admin = Repo.get_by(User, username: "admin")

# Lista de tags padrão
base_tags = [
  %{name: "Urgente", color: "#ef4444", description: "Pedidos que precisam de atenção imediata"},
  %{name: "Pendente", color: "#f59e0b", description: "Pedidos aguardando resposta"},
  %{name: "VIP", color: "#fbbf24", description: "Cliente VIP ou prioridade alta"},
  %{name: "Reclamação", color: "#dc2626", description: "Pedido com reclamação do cliente"},
  %{name: "Aguardando Retorno", color: "#3b82f6", description: "Aguardando resposta do cliente ou setor"},
  %{name: "Aprovado", color: "#10b981", description: "Pedido aprovado"},
  %{name: "Cancelado", color: "#6b7280", description: "Pedido cancelado"},
  %{name: "Em Análise", color: "#6366f1", description: "Pedido em análise"},
  %{name: "Financeiro", color: "#0ea5e9", description: "Pedido relacionado ao financeiro"},
  %{name: "Logística", color: "#8b5cf6", description: "Pedido relacionado à logística"},
  %{name: "Suporte", color: "#06b6d4", description: "Pedido de suporte/técnico"},
  %{name: "Novo Cliente", color: "#22d3ee", description: "Pedido de novo cliente"},
  %{name: "Alto Valor", color: "#a21caf", description: "Pedido de alto valor"},
  %{name: "Entrega Expressa", color: "#f472b6", description: "Pedido com entrega expressa"}
]

Enum.each(base_tags, fn tag_attrs ->
  Repo.insert!(%Tag{
    name: tag_attrs.name,
    color: tag_attrs.color,
    description: tag_attrs.description,
    is_active: true,
    created_by: admin.id,
    store_id: store.id
  })
end)

IO.puts("Tags padrão criadas com sucesso!")

IO.puts("Seeds executados com sucesso!")
