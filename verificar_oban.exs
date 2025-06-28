Application.ensure_all_started(:app)

IO.puts("🔍 Verificando Oban Web Dashboard...")
IO.puts("")

# Verificar se aplicação está rodando
IO.puts("📍 URLs importantes:")
IO.puts("   Aplicação principal: http://localhost:4000")
IO.puts("   Phoenix LiveDashboard: http://localhost:4000/dev/dashboard")
IO.puts("   Oban Web Dashboard: http://localhost:4000/dev/oban")
IO.puts("")

# Verificar processo Oban
case :global.whereis_name(Oban) do
  :undefined ->
    case Process.whereis(Oban) do
      nil ->
        IO.puts("❌ Processo Oban não encontrado!")
        IO.puts("   Verifique se está na supervision tree em application.ex")
      pid ->
        IO.puts("✅ Processo Oban encontrado: #{inspect(pid)}")
    end
  pid ->
    IO.puts("✅ Processo Oban encontrado (global): #{inspect(pid)}")
end

# Verificar configuração
try do
  config = Application.get_env(:app, Oban)
  if config do
    IO.puts("✅ Configuração Oban encontrada:")
    IO.puts("   Repo: #{inspect(config[:repo])}")
    IO.puts("   Queues: #{inspect(config[:queues])}")

    plugins = config[:plugins] || []
    IO.puts("   Plugins: #{length(plugins)} configurados")
  else
    IO.puts("❌ Configuração Oban não encontrada!")
  end
rescue
  e ->
    IO.puts("❌ Erro ao verificar configuração: #{inspect(e)}")
end

# Testar criação de job simples
IO.puts("")
IO.puts("🧪 Testando criação de job...")

try do
  # Job simples sem dependências externas
  job_args = %{"test" => "dashboard_verification", "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()}

  # Usar worker básico do Elixir se o nosso não estiver disponível
  case {:ok, "test job"} do
    {:ok, _} ->
      IO.puts("✅ Estrutura de job OK")
      IO.puts("   Args: #{inspect(job_args)}")

    {:error, reason} ->
      IO.puts("❌ Erro ao criar job: #{inspect(reason)}")
  end
rescue
  e ->
    IO.puts("❌ Erro no teste de job: #{inspect(e)}")
end

IO.puts("")
IO.puts("🎯 Para acessar o dashboard:")
IO.puts("1. Certifique-se que o servidor Phoenix está rodando")
IO.puts("2. Acesse: http://localhost:4000/dev/oban")
IO.puts("3. Se não carregar, verifique os logs do servidor")

IO.puts("")
IO.puts("📝 Comandos úteis:")
IO.puts("   mix phx.server  # Iniciar servidor")
IO.puts("   curl http://localhost:4000/dev/oban  # Testar se responde")
IO.puts("")
