IO.puts("🎨 Design Minimalista do Monitor Oban")
IO.puts("=" |> String.duplicate(50))

# Verificar se servidor está rodando
case HTTPoison.get("http://localhost:4000") do
  {:ok, %HTTPoison.Response{status_code: 200}} ->
    IO.puts("✅ Servidor Phoenix ativo")
  _ ->
    IO.puts("❌ Servidor não está rodando!")
    IO.puts("   Execute: mix phx.server")
    System.halt(1)
end

IO.puts("")
IO.puts("🎯 Monitor Oban com Design Minimalista")
IO.puts("   URL: http://localhost:4000/dev/oban")

IO.puts("")
IO.puts("🔄 Criando jobs para demonstração...")

# Criar alguns jobs para aparecer no monitor
jobs_para_demo = [
  %{
    "tipo" => "design_demo_1",
    "api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12",
    "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
  },
  %{
    "tipo" => "design_demo_2",
    "test" => true,
    "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
  },
  %{
    "tipo" => "design_demo_agendado",
    "test" => true,
    "agendado" => "30 segundos",
    "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
  }
]

# Job para api_sync (imediato)
case JuruConnect.Workers.SupervisorDataWorker.new(Enum.at(jobs_para_demo, 0), queue: :api_sync) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job imediato criado na fila api_sync (ID: #{job.id})")
  {:error, reason} ->
    IO.puts("❌ Erro: #{inspect(reason)}")
end

# Job para default (imediato)
case JuruConnect.Workers.SupervisorDataWorker.new(Enum.at(jobs_para_demo, 1), queue: :default) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job imediato criado na fila default (ID: #{job.id})")
  {:error, reason} ->
    IO.puts("❌ Erro: #{inspect(reason)}")
end

# Job agendado (30 segundos)
case JuruConnect.Workers.SupervisorDataWorker.new(Enum.at(jobs_para_demo, 2), queue: :api_sync, in: 30) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Job agendado criado para 30s (ID: #{job.id})")
  {:error, reason} ->
    IO.puts("❌ Erro: #{inspect(reason)}")
end

IO.puts("")
IO.puts("📊 Verificando estatísticas atuais...")

# Consultar stats do banco
try do
  query = """
  SELECT
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE state = 'available') as available,
    COUNT(*) FILTER (WHERE state = 'executing') as executing,
    COUNT(*) FILTER (WHERE state IN ('retryable', 'discarded')) as failed
  FROM oban_jobs
  WHERE inserted_at >= NOW() - INTERVAL '1 hour'
  """

  case App.Repo.query(query, []) do
    {:ok, %{rows: [[total, available, executing, failed]]}} ->
      IO.puts("   Total de jobs (última hora): #{total}")
      IO.puts("   Disponíveis: #{available}")
      IO.puts("   Executando: #{executing}")
      IO.puts("   Falharam: #{failed}")
    _ ->
      IO.puts("   Não foi possível consultar estatísticas")
  end
rescue
  _ ->
    IO.puts("   Erro ao consultar banco de dados")
end

IO.puts("")
IO.puts("🎨 CARACTERÍSTICAS DO NOVO DESIGN:")
IO.puts("")
IO.puts("✨ TIPOGRAFIA MINIMALISTA:")
IO.puts("   • Fonte monospace padronizada")
IO.puts("   • Headers em maiúsculas")
IO.puts("   • Tamanhos de fonte uniformes")
IO.puts("   • Peso de fonte reduzido")
IO.puts("")
IO.puts("🎯 PALETA DE CORES LIMPA:")
IO.puts("   • Background: cinza claro")
IO.puts("   • Cards: branco com bordas simples")
IO.puts("   • Texto: tons de cinza")
IO.puts("   • Cores funcionais apenas para status")
IO.puts("")
IO.puts("📐 LAYOUT SIMPLIFICADO:")
IO.puts("   • Sem bordas arredondadas")
IO.puts("   • Sem sombras decorativas")
IO.puts("   • Espaçamento otimizado")
IO.puts("   • Elementos essenciais apenas")
IO.puts("")
IO.puts("🔘 INTERAÇÕES SUTIS:")
IO.puts("   • Botões discretos")
IO.puts("   • Hover effects suaves")
IO.puts("   • Links sublinhados")
IO.puts("   • Transições suaves")
IO.puts("")

IO.puts("🎛️ O QUE VOCÊ VERÁ NO MONITOR:")
IO.puts("")
IO.puts("1️⃣  HEADER LIMPO:")
IO.puts("    • Título simples: 'Monitor Oban'")
IO.puts("    • Subtítulo: 'Sistema de monitoramento de jobs'")
IO.puts("    • Timestamp minimalista no canto")
IO.puts("")
IO.puts("2️⃣  ESTATÍSTICAS EM CARDS BRANCOS:")
IO.puts("    • TOTAL, DISPONÍVEIS, EXECUTANDO, FALHARAM")
IO.puts("    • Números grandes em fonte mono")
IO.puts("    • Labels pequenos em maiúsculas")
IO.puts("")
IO.puts("3️⃣  BOTÃO DE TESTE SIMPLES:")
IO.puts("    • Fundo cinza escuro")
IO.puts("    • Texto em fonte mono")
IO.puts("    • Sem ícones decorativos")
IO.puts("")
IO.puts("4️⃣  TABELA DE FILAS LIMPA:")
IO.puts("    • Headers em fonte mono maiúscula")
IO.puts("    • Status com cores funcionais")
IO.puts("    • Links de ação sublinhados")
IO.puts("")
IO.puts("5️⃣  TABELA DE JOBS ORGANIZADA:")
IO.puts("    • Dados em fonte mono")
IO.puts("    • Estados com cores sutis")
IO.puts("    • Hover effects discretos")
IO.puts("")

IO.puts("=" |> String.duplicate(50))
IO.puts("✨ DESIGN MINIMALISTA PRONTO!")
IO.puts("")
IO.puts("👉 Acesse agora: http://localhost:4000/dev/oban")
IO.puts("")
IO.puts("🎯 Recursos disponíveis:")
IO.puts("   • Monitoramento em tempo real")
IO.puts("   • Controle de filas")
IO.puts("   • Visualização de jobs")
IO.puts("   • Interface limpa e profissional")
IO.puts("   • Design responsivo")
IO.puts("")
IO.puts("🎨 Aproveite a nova experiência visual!")
IO.puts("   Interface otimizada para produtividade")
IO.puts("   Menos distrações, mais foco nos dados")
IO.puts("   Design atemporal e elegante")
