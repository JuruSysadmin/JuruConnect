# Teste de autenticação
{:ok, _} = Application.ensure_all_started(:app)

# Teste do usuário admin
case App.Accounts.authenticate_user("admin_teste", "Admin123!@#") do
  {:ok, user} ->
    IO.puts("✅ Autenticação admin_teste: SUCESSO")
    IO.inspect(user, label: "Usuário")
  {:error, reason} ->
    IO.puts("❌ Autenticação admin_teste: FALHOU")
    IO.inspect(reason, label: "Erro")
end

# Teste com Auth.Manager
auth_params = %{
  username: "admin_teste",
  password: "Admin123!@#",
  ip_address: "127.0.0.1"
}

case App.Auth.Manager.authenticate(auth_params) do
  {:ok, result} ->
    IO.puts("✅ Auth.Manager admin_teste: SUCESSO")
    IO.inspect(result, label: "Resultado")
  {:error, reason} ->
    IO.puts("❌ Auth.Manager admin_teste: FALHOU")
    IO.inspect(reason, label: "Erro")
end

IO.puts("✨ Teste concluído!")
