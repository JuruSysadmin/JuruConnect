defmodule Mix.Tasks.CreateAdmin do
  @moduledoc """
  Mix task para criar um usuário administrador padrão.

  ## Uso

      mix create_admin

  ## Opções

      --username    Nome de usuário (padrão: "admin")
      --name        Nome completo (padrão: "Administrador")
      --password    Senha (padrão: "admin123")
      --force       Força a criação mesmo se o usuário já existir

  ## Exemplos

      mix create_admin
      mix create_admin --username "superadmin" --name "Super Admin" --password "senha123"
      mix create_admin --force
  """

  use Mix.Task

  alias App.{Accounts, Repo}
  alias App.Stores.Store

  @shortdoc "Cria um usuário administrador padrão"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _errors} = OptionParser.parse(args,
      strict: [
        username: :string,
        name: :string,
        password: :string,
        force: :boolean
      ],
      aliases: [
        u: :username,
        n: :name,
        p: :password,
        f: :force
      ]
    )

    username = Keyword.get(opts, :username, "admin")
    name = Keyword.get(opts, :name, "Administrador")
    password = Keyword.get(opts, :password, "admin123")
    force = Keyword.get(opts, :force, false)

    create_admin_user(username, name, password, force)
  end

  defp create_admin_user(username, name, password, force) do
    IO.puts("🔧 Criando usuário administrador...")
    IO.puts("   Username: #{username}")
    IO.puts("   Nome: #{name}")
    IO.puts("   Senha: #{password}")
    IO.puts("")

    # Verificar se o usuário já existe
    case Accounts.get_user_by_username(username) do
      nil ->
        # Usuário não existe, vamos criar
        create_new_admin(username, name, password)

      existing_user ->
        if force do
          IO.puts("⚠️  Usuário '#{username}' já existe. Atualizando...")
          update_existing_admin(existing_user, name, password)
        else
          IO.puts("❌ Usuário '#{username}' já existe!")
          IO.puts("   Use --force para atualizar o usuário existente")
          IO.puts("   Ou use um username diferente com --username")
          System.halt(1)
        end
    end
  end

  defp create_new_admin(username, name, password) do
    # Buscar ou criar loja padrão
    store = get_or_create_default_store()

    user_attrs = %{
      username: username,
      name: name,
      role: "admin",
      password: password,
      store_id: store.id
    }

    case Accounts.create_user(user_attrs) do
      {:ok, user} ->
        IO.puts("✅ Usuário administrador criado com sucesso!")
        IO.puts("   ID: #{user.id}")
        IO.puts("   Username: #{user.username}")
        IO.puts("   Nome: #{user.name}")
        IO.puts("   Role: #{user.role}")
        IO.puts("   Loja: #{store.name}")
        IO.puts("")
        IO.puts("🔑 Credenciais de acesso:")
        IO.puts("   Username: #{username}")
        IO.puts("   Senha: #{password}")

      {:error, changeset} ->
        IO.puts("❌ Erro ao criar usuário administrador:")
        IO.puts("   #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  defp update_existing_admin(user, name, password) do
    update_attrs = %{
      name: name,
      role: "admin",
      password: password
    }

    case Accounts.update_user(user, update_attrs) do
      {:ok, updated_user} ->
        IO.puts("✅ Usuário administrador atualizado com sucesso!")
        IO.puts("   ID: #{updated_user.id}")
        IO.puts("   Username: #{updated_user.username}")
        IO.puts("   Nome: #{updated_user.name}")
        IO.puts("   Role: #{updated_user.role}")
        IO.puts("")
        IO.puts("🔑 Credenciais de acesso:")
        IO.puts("   Username: #{updated_user.username}")
        IO.puts("   Senha: #{password}")

      {:error, changeset} ->
        IO.puts("❌ Erro ao atualizar usuário administrador:")
        IO.puts("   #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  defp get_or_create_default_store do
    case Repo.get_by(Store, name: "Loja Padrão") do
      nil ->
        IO.puts("📦 Criando loja padrão...")
        %Store{
          name: "Loja Padrão",
          location: "Localização Padrão"
        }
        |> Repo.insert!()

      existing_store ->
        existing_store
    end
  end
end
