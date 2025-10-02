defmodule App.TreatyCommentsTest do
  use App.DataCase, async: true

  alias App.TreatyComments
  alias App.TreatyComments.TreatyComment

  setup do
    # Limpar dados anteriores
    App.Repo.delete_all(App.TreatyComments.TreatyComment)
    App.Repo.delete_all(App.Treaties.Treaty)
    App.Repo.delete_all(App.Accounts.User)
    App.Repo.delete_all("stores")

    # Criar store para o teste
    store_id = "550e8400-e29b-41d4-a716-446655440000"
    App.Repo.insert_all("stores", [
      %{
        id: Ecto.UUID.dump!(store_id),
        name: "Loja Teste",
        location: "Localização Teste",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    # Criar usuários para os testes
    {:ok, admin} = create_user(%{
      username: "admin",
      name: "Admin User",
      role: "admin",
      password: "password123",
      store_id: store_id
    })

    {:ok, user} = create_user(%{
      username: "user",
      name: "admin User",
      role: "customer",
      password: "password123",
      store_id: store_id
    })

    # Criar tratativa
    {:ok, treaty} = create_treaty(%{
      title: "Pedido de Estoque",
      description: "Cliente solicitando quantidade de produtos",
      created_by: admin.id,
      store_id: admin.store_id,
      status: "active"
    })

    %{admin: admin, user: user, treaty: treaty}
  end

  describe "create_comment/3" do
    test "cria um comentário interno com sucesso", %{admin: admin, treaty: treaty} do
      attrs = %{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Nota interna: Cliente precisa de urgência"
      }

      {:ok, comment} = TreatyComments.create_comment(attrs)

      assert comment.treaty_id == treaty.id
      assert comment.user_id == admin.id
      assert comment.content == "Nota interna: Cliente precisa de urgência"
      assert comment.is_internal == true
      assert comment.comment_type == "note"
    end

    test "valida campos obrigatórios" do
      {:error, changeset} = TreatyComments.create_comment(%{})

      assert "can't be blank" in errors_on(changeset).treaty_id
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).content
    end

    test "valida tamanho máximo do conteúdo" do
      long_content = String.duplicate("a", 2001)

      {:error, changeset} = TreatyComments.create_comment(%{
        treaty_id: "valid-id",
        user_id: "valid-id",
        content: long_content
      })

      assert "should be at most 2000 character(s)" in errors_on(changeset).content
    end

    test "agrupa comentários por tipo corretamente", %{admin: admin, treaty: treaty} do
      # Criar comentário interno
      {:ok, internal} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário interno",
        comment_type: "internal_note"
      })

      # Criar comentário público
      {:ok, public} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário público",
        comment_type: "public_note"
      })

      assert internal.comment_type == "internal_note"
      assert public.comment_type == "public_note"
    end
  end

  describe "get_treaty_comments/2" do
    test "lista comentários de uma tratativa", %{admin: admin, treaty: treaty} do
      # Criar alguns comentários
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Primeiro comentário"
      })

      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Segundo comentário"
      })

      comments = TreatyComments.get_treaty_comments(treaty.id)

      assert length(comments) == 2
      assert Enum.all?(comments, &(&1.treaty_id == treaty.id))
    end

    test "filtra comentários por tipo", %{admin: admin, treaty: treaty} do
      # Criar comentário interno
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário interno",
        comment_type: "internal_note"
      })

      # Criar comentário público
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário público",
        comment_type: "public_note"
      })

      internal_comments = TreatyComments.get_treaty_comments(treaty.id, :internal)
      public_comments = TreatyComments.get_treaty_comments(treaty.id, :public)

      assert length(internal_comments) == 1
      assert length(public_comments) == 1
      assert hd(internal_comments).comment_type == "internal_note"
      assert hd(public_comments).comment_type == "public_note"
    end

    test "ordena comentários por data de criação decrescente", %{admin: admin, treaty: treaty} do
      # Criar primeiro comentário
      {:ok, comment1} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Primeiro comentário"
      })

      # Aguardar um momento e criar segundo comentário
      Process.sleep(10)

      {:ok, comment2} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Segundo comentário"
      })

      comments = TreatyComments.get_treaty_comments(treaty.id)

      assert length(comments) == 2
      assert hd(comments).id == comment2.id  # Mais recente primeiro
    end
  end

  describe "update_comment/2" do
    test "atualiza conteúdo do comentário", %{admin: admin, treaty: treaty} do
      {:ok, comment} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Conteúdo original"
      })

      {:ok, updated} = TreatyComments.update_comment(comment.id, %{
        content: "Conteúdo atualizado"
      })

      assert updated.content == "Conteúdo atualizado"
      assert updated.id == comment.id
    end

    test "retorna erro ao tentar atualizar comentário inexistente" do
      invalid_id = Ecto.UUID.generate()

      {:error, :not_found} = TreatyComments.update_comment(invalid_id, %{
        content: "Novo conteúdo"
      })
    end

    test "valida tamanho máximo do conteúdo atualizado" do
      long_content = String.duplicate("a", 2001)

      # Primeiro criar o comentário
      attrs = %{
        treaty_id: "valid-id",
        user_id: "valid-id",
        content: "Conteúdo original"
      }

      # Mock do insert para teste de validação
      {:error, changeset} = TreatyComments.update_comment("valid-id", %{
        content: long_content
      })

      assert "should be at most 2000 character(s)" in errors_on(changeset).content
    end
  end

  describe "delete_comment/1" do
    test "remove comentário com sucesso", %{admin: admin, treaty: treaty} do
      {:ok, comment} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        status: "active",
        content: "Comentário para remover"
      })

      {:ok, deleted} = TreatyComments.delete_comment(comment.id)

      assert deleted.status == "deleted"
    end

    test "retorna erro ao tentar remover comentário inexistente" do
      invalid_id = Ecto.UUID.generate()

      {:error, :not_found} = TreatyComments.delete_comment(invalid_id)
    end

    test "retorna erro ao tentar remover comentário já deletado", %{admin: admin, treaty: treaty} do
      {:ok, comment} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário para testar"
      })

      # Deletar primeira vez
      {:ok, _} = TreatyComments.delete_comment(comment.id)

      # Tentar deletar novamente
      {:error, :not_found} = TreatyComments.delete_comment(comment.id)
    end
  end

  describe "get_comment_stats/1" do
    test "calcula estatísticas corretas dos comentários", %{admin: admin, treaty: treaty} do
      # Criar comentários de diferentes tipos
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário interno",
        comment_type: "internal_note"
      })

      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Comentário público",
        comment_type: "public_note"
      })

      {:ok, comment3} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Outro comentário interno",
        comment_type: "internal_note"
      })

      # Deletar um comentário
      {:ok, _} = TreatyComments.delete_comment(comment3.id)

      stats = TreatyComments.get_comment_stats(treaty.id)

      assert stats.total_comments == 3
      assert stats.active_comments == 2
      assert stats.deleted_comments == 1
      assert stats.internal_comments == 2
      assert stats.public_comments == 1
      assert stats.comments_by_user[admin.id] == 2
    end

    test "retorna zeros quando não há comentários" do
      stats = TreatyComments.get_comment_stats("non-existent-id")

      assert stats.total_comments == 0
      assert stats.active_comments == 0
      assert stats.deleted_comments == 0
      assert stats.internal_comments == 0
      assert stats.public_comments == 0
    end
  end

  describe "search_comments/2" do
    test "busca comentários por conteúdo", %{admin: admin, treaty: treaty} do
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Este contém a palavra urgência"
      })

      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "Este comentário não é relevante"
      })

      results = TreatyComments.search_comments("urgência")

      assert length(results) == 1
      assert hd(results).content == "Este contém a palavra urgência"
    end

    test "busca case insensitive", %{admin: admin, treaty: treaty} do
      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty.id,
        user_id: admin.id,
        content: "CLIENTE precisa de ajuda URGENTE"
      })

      results_lower = TreatyComments.search_comments("cliente")
      results_upper = TreatyComments.search_comments("CLIENTE")

      assert length(results_lower) == 1
      assert length(results_upper) == 1
      assert hd(results_lower).id == hd(results_upper).id
    end

    test "filtra busca por tratativa específica", %{
      admin: admin,
      treaty: treaty1,
      treaty2: treaty2
    } do
      # Criar segunda tratativa
      {:ok, treaty2} = create_treaty(%{
        title: "Segunda tratativa",
        description: "Outra tratativa",
        created_by: admin.id,
        store_id: admin.store_id
      })

      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty1.id,
        user_id: admin.id,
        content: "Comentário sobre produto específico"
      })

      {:ok, _} = TreatyComments.create_comment(%{
        treaty_id: treaty2.id,
        user_id: admin.id,
        content: "Outro comentário sobre produto específico"
      })

      # Buscar apenas na primeira tratativa
      results = TreatyComments.search_comments("produto específico", treaty1.id)

      assert length(results) == 1
      assert hd(results).treaty_id == treaty1.id
    end
  end

  # Funções auxiliares de teste
  defp create_user(attrs) do
    App.Accounts.create_user(attrs)
  end

  defp create_treaty(attrs) do
    App.Treaties.create_treaty(attrs)
  end
end
