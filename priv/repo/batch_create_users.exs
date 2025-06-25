# priv/repo/batch_create_users.exs
alias App.{Accounts, Repo}
alias App.Stores.Store

# Busca a loja pelo nome
store_id = Repo.get_by!(Store, name: "Loja Padrão").id

users = [
  %{username: "user1", password: "senha123", name: "Usuário 1", role: "admin",   store_id: store_id},
  %{username: "user2", password: "senha456", name: "Usuário 2", role: "manager", store_id: store_id},
  %{username: "user3", password: "senha789", name: "Usuário 3", role: "clerk",   store_id: store_id}
]

users
|> Task.async_stream(
     &Accounts.create_user/1,
     max_concurrency: System.schedulers_online(),
     timeout: :infinity
   )
|> Enum.each(fn
  {:ok, {:ok, %Accounts.User{username: u}}} ->
    IO.puts(" criado #{u}")

  {:ok, {:error, cs}} ->
    IO.puts(" erro em #{inspect(cs.data.username)}")
    IO.inspect(cs.errors)

  {:exit, reason} ->
    IO.puts("  abortou: #{inspect(reason)}")
end)
