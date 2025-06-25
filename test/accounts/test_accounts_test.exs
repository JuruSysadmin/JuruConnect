defmodule App.AccountsTest do
  use ExUnit.Case, async: true

  alias App.Accounts
  alias App.Accounts.User

  defmodule Pbkdf2Mock do
    def verify_pass("valid_password", _hash), do: true
    def verify_pass(_, _), do: false
  end

  setup do
    user = %User{
      id: 1,
      username: "testuser",
      password_hash: "hashed_password"
    }

    {:ok, user: user}
  end

  test "retorna {:ok, user} com credenciais válidas", %{user: user} do
    deps = %{
      get_user: fn
        "testuser" -> user
        _ -> nil
      end,
      verify: &Pbkdf2Mock.verify_pass/2
    }

    assert {:ok, ^user} = Accounts.authenticate_user("testuser", "valid_password", deps)
  end

  test "retorna {:error, :unauthorized} com senha inválida", %{user: user} do
    deps = %{
      get_user: fn
        "testuser" -> user
        _ -> nil
      end,
      verify: &Pbkdf2Mock.verify_pass/2
    }

    assert {:error, :unauthorized} =
             Accounts.authenticate_user("testuser", "wrong_password", deps)
  end

  test "retorna {:error, :unauthorized} com usuário inexistente" do
    deps = %{
      get_user: fn _ -> nil end,
      verify: &Pbkdf2Mock.verify_pass/2
    }

    assert {:error, :unauthorized} = Accounts.authenticate_user("unknown", "any_password", deps)
  end
end
