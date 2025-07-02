defmodule AppWeb.Integration.LoginFlowTest do
  use AppWeb.ConnCase, async: true

  describe "Login Flow Integration Test" do
    setup do
      # Criar usuário de teste
      user = insert(:user,
        username: "testuser",
        password_hash: Argon2.hash_pwd_salt("password123"),
        role: "user"
      )
      {:ok, user: user}
    end

    test "successful login flow", %{conn: conn, user: user} do
      # 1. Acessar página de login
      conn = get(conn, ~p"/auth/login")
      assert html_response(conn, 200)

      # 2. Enviar credenciais válidas
      conn = post(conn, ~p"/sessions", %{
        "user" => %{
          "username" => user.username,
          "password" => "password123"
        }
      })

      # 3. Deve redirecionar para dashboard
      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :info) == "Bem-vindo de volta!"

      # 4. Deve estar autenticado
      assert get_session(conn, :access_token)
    end

    test "failed login with invalid credentials", %{conn: conn} do
      # 1. Acessar página de login
      conn = get(conn, ~p"/auth/login")
      assert html_response(conn, 200)

      # 2. Enviar credenciais inválidas
      conn = post(conn, ~p"/sessions", %{
        "user" => %{
          "username" => "invalid_user",
          "password" => "wrong_password"
        }
      })

      # 3. Deve permanecer na página de login com erro
      assert html_response(conn, 200)
      assert get_flash(conn, :error) == "Usuário ou senha inválidos."

      # 4. Não deve estar autenticado
      refute get_session(conn, :access_token)
    end

    test "logout flow", %{conn: conn, user: user} do
      # 1. Fazer login primeiro
      {:ok, token, _claims} = AppWeb.Auth.Guardian.encode_and_sign(user)

      conn =
        conn
        |> put_session(:access_token, token)
        |> AppWeb.Auth.GuardianPlug.sign_in(user)

      # 2. Verificar que está autenticado
      assert AppWeb.Auth.GuardianPlug.authenticated?(conn)

      # 3. Fazer logout
      conn = get(conn, ~p"/logout")

      # 4. Deve redirecionar para login
      assert redirected_to(conn) == "/auth/login"
      assert get_flash(conn, :info) == "Você saiu com sucesso."
    end

    test "protected route requires authentication", %{conn: conn} do
      # 1. Tentar acessar rota protegida sem autenticação
      conn = get(conn, ~p"/dashboard")

      # 2. Deve redirecionar para login
      assert redirected_to(conn) == "/auth/login"
      assert get_flash(conn, :error) == "Você precisa estar logado para acessar esta página."
    end

    test "protected route allows authenticated user", %{conn: conn, user: user} do
      # 1. Autenticar usuário
      conn = AppWeb.Auth.GuardianPlug.sign_in(conn, user)

      # 2. Acessar rota protegida
      conn = get(conn, ~p"/dashboard")

      # 3. Deve permitir acesso (não redirecionar)
      assert html_response(conn, 200)
    end

    test "admin route requires admin role", %{conn: conn} do
      # 1. Criar usuário regular
      regular_user = insert(:user, role: "user")

      # 2. Autenticar usuário regular
      conn = AppWeb.Auth.GuardianPlug.sign_in(conn, regular_user)

      # 3. Tentar acessar rota admin
      conn = get(conn, ~p"/admin/security")

      # 4. Deve redirecionar com erro
      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :error) == "Acesso negado. Apenas administradores e gerentes podem acessar esta página."
    end

    test "admin route allows admin user", %{conn: conn} do
      # 1. Criar usuário admin
      admin_user = insert(:user, role: "admin")

      # 2. Autenticar usuário admin
      conn = AppWeb.Auth.GuardianPlug.sign_in(conn, admin_user)

      # 3. Acessar rota admin
      conn = get(conn, ~p"/admin/security")

      # 4. Deve permitir acesso
      assert html_response(conn, 200)
    end

    test "handles malformed tokens gracefully", %{conn: conn} do
      # 1. Colocar token malformado na sessão
      conn =
        conn
        |> put_session("guardian_default_token", "malformed.token.here")

      # 2. Acessar página pública
      conn = get(conn, ~p"/")

      # 3. Deve funcionar normalmente (token é limpo pelo GuardianSessionPlug)
      assert html_response(conn, 200)

      # 4. Acessar rota protegida deve redirecionar para login
      conn = get(conn, ~p"/dashboard")
      assert redirected_to(conn) == "/auth/login"
    end
  end
end
