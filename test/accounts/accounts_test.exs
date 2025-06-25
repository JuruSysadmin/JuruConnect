defmodule App.AccountsTest do
  use App.DataCase

  alias App.Accounts

  @store_id "550e8400-e29b-41d4-a716-446655440000"

  setup do
    # Criar uma loja para os testes
    App.Repo.insert_all("stores", [
      %{
        id: Ecto.UUID.dump!(@store_id),
        name: "Loja Teste",
        location: "Localização Teste",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    :ok
  end

  describe "get_user!/1" do
    test "deve retornar um usuário quando o ID existe" do
      # Given: dado que  um usuário existe no banco
      user_attrs = %{
        username: "joao123",
        name: "João Silva",
        role: "admin",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, user} = Accounts.create_user(user_attrs)

      # When: Quando  buscamos o usuário pelo ID
      found_user = Accounts.get_user!(user.id)

      # Then: Então o usuário correto é retornado
      assert found_user.id == user.id
      assert found_user.username == "joao123"
      assert found_user.name == "João Silva"
    end

    test "deve levantar erro quando o ID não existe" do
      # Given: dado que um ID que não existe
      non_existent_id = "550e8400-e29b-41d4-a716-446655440001"

      # When/Then: deve levantar Ecto.NoResultsError
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(non_existent_id)
      end
    end
  end

  describe "get_user_by_username/1" do
    test "deve retornar um usuário quando o username existe" do
      # Given: dado que  um usuário existe no banco
      user_attrs = %{
        username: "maria456",
        name: "Maria Santos",
        role: "manager",
        password: "senha456",
        store_id: @store_id
      }

      {:ok, _user} = Accounts.create_user(user_attrs)

      # When: buscamos o usuário pelo username
      found_user = Accounts.get_user_by_username("maria456")

      # Then: o usuário correto é retornado
      assert found_user.username == "maria456"
      assert found_user.name == "Maria Santos"
    end

    test "deve retornar nil quando o username não existe" do
      # Given: um username que não existe
      non_existent_username = "usuario_inexistente"

      # When: buscamos o usuário pelo username
      result = Accounts.get_user_by_username(non_existent_username)

      # Then: nil é retornado
      assert result == nil
    end
  end

  describe "create_user/1" do
    test "deve criar um usuário válido" do
      # Given:Dado que o usuarios se cadastra com  atributos válidos de usuário
      attrs = %{
        username: "novo_usuario",
        name: "Novo Usuário",
        role: "clerk",
        password: "senha123",
        store_id: @store_id
      }

      # When: Quando	criamos o usuário
      result = Accounts.create_user(attrs)

      # Then: Então o usuário é criado com sucesso
      assert {:ok, user} = result
      assert user.username == "novo_usuario"
      assert user.name == "Novo Usuário"
      assert user.role == "clerk"
      assert user.password_hash != nil
    end

    test "deve falhar quando os atributos são inválidos" do
      # Given: atributos inválidos (username muito curto)
      attrs = %{
        username: "ab",
        name: "Usuário Inválido",
        role: "admin",
        password: "senha123",
        store_id: @store_id
      }

      # When: tentamos criar o usuário
      result = Accounts.create_user(attrs)

      # Then: deve falhar com erro de validação
      assert {:error, changeset} = result
      assert %{username: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end
  end

  describe "update_user/2" do
    test "deve atualizar um usuário existente" do
      # Given: Dado que	um usuário existe no banco
      user_attrs = %{
        username: "usuario_atualizar",
        name: "Nome Original",
        role: "manager",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, user} = Accounts.create_user(user_attrs)

      # When: Quando atualizamos o usuário
      update_attrs = %{
        name: "Nome Atualizado",
        role: "admin",
        website: "https://novosite.com"
      }

      result = Accounts.update_user(user, update_attrs)

      # Then: Então o usuário é atualizado com sucesso
      assert {:ok, updated_user} = result
      assert updated_user.name == "Nome Atualizado"
      assert updated_user.role == "admin"
      assert updated_user.website == "https://novosite.com"
    end

    test "deve falhar quando os atributos de atualização são inválidos" do
      # Given: um usuário existe no banco
      user_attrs = %{
        username: "usuario_invalido",
        name: "Nome Original",
        role: "manager",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, user} = Accounts.create_user(user_attrs)

      # When: tentamos atualizar com dados inválidos
      invalid_attrs = %{username: "ab"}
      result = Accounts.update_user(user, invalid_attrs)

      # Then: deve falhar com erro de validação
      assert {:error, changeset} = result
      assert %{username: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end
  end

  describe "delete_user/1" do
    test "deve deletar um usuário existente" do
      # Given: Dado que	 um usuário existe no banco
      user_attrs = %{
        username: "usuario_deletar",
        name: "Usuário para Deletar",
        role: "clerk",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, user} = Accounts.create_user(user_attrs)

      # When: Quando deletamos o usuário
      result = Accounts.delete_user(user)

      # Then: Quando o usuário é deletado com sucesso
      assert {:ok, deleted_user} = result
      assert deleted_user.id == user.id

      # And: Então o usuário não existe mais no banco
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(user.id)
      end
    end
  end

  describe "list_users/1" do
    test "deve listar todos os usuários" do
      # Given: Dado que múltiplos usuários existem no banco
      user1_attrs = %{
        username: "usuario1",
        name: "Usuário 1",
        role: "admin",
        password: "senha123",
        store_id: @store_id
      }

      user2_attrs = %{
        username: "usuario2",
        name: "Usuário 2",
        role: "manager",
        password: "senha456",
        store_id: @store_id
      }

      {:ok, _user1} = Accounts.create_user(user1_attrs)
      {:ok, _user2} = Accounts.create_user(user2_attrs)

      # When: Quando listamos todos os usuários
      users = Accounts.list_users()

      # Then: Então todos os usuários são retornados
      assert length(users) >= 2
      usernames = Enum.map(users, & &1.username)
      assert "usuario1" in usernames
      assert "usuario2" in usernames
    end

    test "deve listar usuários com limite" do
      # Given: múltiplos usuários existem no banco
      for i <- 1..5 do
        attrs = %{
          username: "usuario#{i}",
          name: "Usuário #{i}",
          role: "clerk",
          password: "senha#{i}",
          store_id: @store_id
        }

        {:ok, _user} = Accounts.create_user(attrs)
      end

      # When: listamos usuários com limite
      users = Accounts.list_users(limit: 3)

      # Then: apenas 3 usuários são retornados
      assert length(users) == 3
    end
  end

  describe "get_users_by_store/1" do
    test "deve retornar usuários de uma loja específica" do
      # Given: usuários de lojas diferentes
      store1_id = @store_id
      store2_id = "550e8400-e29b-41d4-a716-446655440001"

      # Criar segunda loja
      App.Repo.insert_all("stores", [
        %{
          id: Ecto.UUID.dump!(store2_id),
          name: "Loja 2",
          location: "Localização 2",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      user1_attrs = %{
        username: "usuario_loja1",
        name: "Usuário Loja 1",
        role: "admin",
        password: "senha123",
        store_id: store1_id
      }

      user2_attrs = %{
        username: "usuario_loja2",
        name: "Usuário Loja 2",
        role: "manager",
        password: "senha456",
        store_id: store2_id
      }

      {:ok, _user1} = Accounts.create_user(user1_attrs)
      {:ok, _user2} = Accounts.create_user(user2_attrs)

      # When: buscamos usuários da loja 1
      store1_users = Accounts.get_users_by_store(store1_id)

      # Then: apenas usuários da loja 1 são retornados
      assert length(store1_users) >= 1

      Enum.each(store1_users, fn user ->
        assert user.store_id == store1_id
      end)
    end
  end

  describe "get_users_by_role/1" do
    test "deve retornar usuários com uma função específica" do
      # Given: Dado que	usuários com funções diferentes
      admin_attrs = %{
        username: "admin_user",
        name: "Admin User",
        role: "admin",
        password: "senha123",
        store_id: @store_id
      }

      manager_attrs = %{
        username: "manager_user",
        name: "Manager User",
        role: "manager",
        password: "senha456",
        store_id: @store_id
      }

      {:ok, _admin} = Accounts.create_user(admin_attrs)
      {:ok, _manager} = Accounts.create_user(manager_attrs)

      # When: Quando buscamos usuários admin
      admin_users = Accounts.get_users_by_role("admin")

      # Then: apenas usuários admin são retornados
      assert length(admin_users) >= 1

      Enum.each(admin_users, fn user ->
        assert user.role == "admin"
      end)
    end
  end

  describe "authenticate_user/3" do
    test "deve autenticar um usuário com credenciais válidas" do
      # Given: Dado que	 um usuário existe no banco
      user_attrs = %{
        username: "usuario_auth",
        name: "Usuário Auth",
        role: "admin",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, _user} = Accounts.create_user(user_attrs)

      # When: tentamos autenticar com credenciais corretas
      result = Accounts.authenticate_user("usuario_auth", "senha123")

      # Then: Então a autenticação é bem-sucedida
      assert {:ok, user} = result
      assert user.username == "usuario_auth"
    end

    test "deve falhar com senha incorreta" do
      # Given: Dado que	 um usuário existe no banco
      user_attrs = %{
        username: "usuario_senha_errada",
        name: "Usuário Senha Errada",
        role: "manager",
        password: "senha123",
        store_id: @store_id
      }

      {:ok, _user} = Accounts.create_user(user_attrs)

      # When: Quando tentamos autenticar com senha incorreta
      result = Accounts.authenticate_user("usuario_senha_errada", "senha_errada")

      # Then: Então a autenticação falha
      assert {:error, :unauthorized} = result
    end

    test "deve falhar com username inexistente" do
      # Given: Dado que um username que não existe
      non_existent_username = "usuario_inexistente"

      # When: Quando tentamos autenticar com username inexistente
      result = Accounts.authenticate_user(non_existent_username, "senha123")

      # Then: Então a autenticação falha
      assert {:error, :unauthorized} = result
    end

    test "deve aceitar dependências customizadas para injeção de dependência" do
      # Given: Dado que dependências customizadas
      custom_deps = %{
        get_user: fn _username -> nil end,
        verify: fn _password, _hash -> false end
      }

      # When: Quando tentamos autenticar com dependências customizadas
      result = Accounts.authenticate_user("qualquer", "senha", custom_deps)

      # Then: Então a autenticação falha (comportamento esperado das dependências)
      assert {:error, :unauthorized} = result
    end
  end
end
