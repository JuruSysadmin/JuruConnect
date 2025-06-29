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

alias App.{Repo, Accounts, Stores}
alias App.Accounts.User
alias App.Stores.Store

require Logger

Logger.info("🌱 Iniciando seeds do JuruConnect...")

# Criar loja padrão se não existir
default_store = try do
  store = Stores.get_store_by!("Loja Padrão")
  Logger.info("📍 Loja padrão já existe: #{store.name}")
  store
rescue
  Ecto.NoResultsError ->
    Logger.info("📍 Criando loja padrão...")
    store = %Stores.Store{
      id: Ecto.UUID.generate(),
      name: "Loja Padrão",
      location: "Matriz - Rua Principal, 123",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    Repo.insert!(store)
end

# Usuários de teste com senhas que atendem às políticas de segurança
test_users = [
  %{
    username: "admin_teste",
    name: "Administrador Teste",
    email: "admin@jurunense.com",
    password: "Admin123!@#",
    role: "admin",
    description: "Usuário administrador para testes completos"
  },
  %{
    username: "manager_teste",
    name: "Gerente Teste",
    email: "manager@jurunense.com",
    password: "Manager456$%^",
    role: "manager",
    description: "Usuário gerente para testes de moderação"
  },
  %{
    username: "vendedor_teste",
    name: "Vendedor Teste",
    email: "vendedor@jurunense.com",
    password: "Vendas789&*()",
    role: "clerk",
    description: "Usuário vendedor para testes básicos"
  }
]

Logger.info("👥 Criando usuários de teste...")

Enum.each(test_users, fn user_data ->
  case Accounts.get_user_by_username(user_data.username) do
    nil ->
      Logger.info("✨ Criando usuário: #{user_data.username} (#{user_data.role})")

      # Criar usuário com validação de senha
      case Accounts.create_user(%{
        username: user_data.username,
        name: user_data.name,
        email: user_data.email,
        password: user_data.password,
        role: user_data.role,
        store_id: default_store.id,
        active: true,
        password_changed_at: Date.to_string(Date.utc_today())
      }) do
        {:ok, user} ->
          Logger.info("✅ Usuário #{user.username} criado com sucesso!")
          Logger.info("   - Nome: #{user.name}")
          Logger.info("   - E-mail: #{user.email}")
          Logger.info("   - Role: #{user.role}")
          Logger.info("   - Loja: #{default_store.name}")

        {:error, changeset} ->
          Logger.error("❌ Erro ao criar usuário #{user_data.username}:")
          Enum.each(changeset.errors, fn {field, {message, _}} ->
            Logger.error("   - #{field}: #{message}")
          end)
      end

    existing_user ->
      Logger.info("⚠️  Usuário #{user_data.username} já existe (ID: #{existing_user.id})")
  end
end)

# Criar alguns dados de exemplo para o dashboard se necessário
Logger.info("📊 Verificando dados do dashboard...")

# Estatísticas de exemplo (opcional)
Logger.info("📈 Seeds concluídas!")

Logger.info("""

🎉 USUÁRIOS DE TESTE CRIADOS COM SUCESSO!

📋 CREDENCIAIS PARA TESTES:

1️⃣  ADMINISTRADOR
   👤 Usuário: admin_teste
   🔐 Senha: Admin123!@#
   📧 E-mail: admin@jurunense.com
   🛡️  Role: admin
   ✨ Acesso: Dashboard de Segurança + Todas as funcionalidades

2️⃣  GERENTE
   👤 Usuário: manager_teste
   🔐 Senha: Manager456$%^
   📧 E-mail: manager@jurunense.com
   🛡️  Role: manager
   ✨ Acesso: Dashboard de Segurança + Moderação

3️⃣  VENDEDOR
   👤 Usuário: vendedor_teste
   🔐 Senha: Vendas789&*()
   📧 E-mail: vendedor@jurunense.com
   🛡️  Role: clerk
   ✨ Acesso: Dashboard básico

🔗 ROTAS PARA TESTE:
   • /auth/login - Interface moderna de login
   • /reset-password - Recuperação de senha
   • /admin/security - Dashboard de segurança (admin/manager)
   • /dashboard - Dashboard principal

🧪 FUNCIONALIDADES PARA TESTAR:
   ✅ Login com rate limiting
   ✅ Recuperação de senha segura
   ✅ Validação de políticas de senha
   ✅ Interface administrativa
   ✅ Logs de segurança
   ✅ Bloqueio/desbloqueio de contas

""")
