# 🎛️ Guia Completo do Oban Web Dashboard

## 🚀 Acesso ao Dashboard

Com o servidor rodando (`mix phx.server`), acesse:
```
http://localhost:4000/dev/oban
```

## 📊 Visão Geral das Seções

### 1. **Overview** (Página Principal)
```
📈 Estatísticas das últimas 24h:
- Jobs processados
- Taxa de sucesso/falha
- Throughput médio
- Latência média
```

### 2. **Jobs** (Monitoramento de Tarefas)
```
📋 Estados dos Jobs:
- Available: Jobs prontos para execução
- Executing: Jobs em execução no momento
- Completed: Jobs concluídos com sucesso
- Retryable: Jobs que falharam e aguardam retry
- Cancelled: Jobs cancelados manualmente
- Discarded: Jobs descartados após tentativas
```

### 3. **Queues** (Gerenciamento de Filas)
```
⚙️ Controles por Fila:
- Pausar/Despausar filas
- Ajustar concorrência
- Ver jobs por fila
- Estatísticas de performance
```

### 4. **Cron** (Jobs Agendados)
```
⏰ Visualização de Cron Jobs:
- Próximas execuções
- Histórico de execuções
- Configuração de schedule
- Status dos jobs periódicos
```

## 🔧 Operações Práticas

### Pausar/Despausar Filas
```
1. Vá para a seção "Queues"
2. Encontre sua fila (ex: api_sync)
3. Clique em "Pause" ou "Start"
4. Confirme a ação
```

### Cancelar Jobs
```
1. Vá para a seção "Jobs"
2. Encontre o job desejado
3. Clique em "Cancel"
4. O job será movido para "Cancelled"
```

### Retry Manual
```
1. Vá para "Jobs" > "Retryable"
2. Selecione o job
3. Clique em "Retry"
4. O job volta para "Available"
```

### Visualizar Detalhes
```
1. Clique em qualquer job
2. Veja informações detalhadas:
   - Args (argumentos)
   - Errors (se houver)
   - Timestamps
   - Meta information
```

## 🎯 Configuração Específica do Projeto

### Suas Filas Configuradas:
```elixir
# config/config.exs
config :app, Oban,
  queues: [
    default: 10,     # Fila padrão - 10 workers
    api_sync: 5      # Fila API - 5 workers
  ]
```

### Seu Cron Job:
```elixir
# Executa a cada hora
{"0 * * * *", JuruConnect.Workers.SupervisorDataWorker}
```

## 🧪 Testando o Dashboard

### Criar Jobs Manuais:
```bash
# Gerar jobs de teste
mix run testar_oban_web.exs

# Depois acesse o dashboard
http://localhost:4000/dev/oban
```

### Comandos Úteis:
```elixir
# No IEx
iex -S mix

# Criar job manual
%{"api_url" => "http://10.1.1.108:8065/api/v1/dashboard/sale/12"}
|> JuruConnect.Workers.SupervisorDataWorker.new()
|> Oban.insert()

# Ver status das filas
Oban.peek_queue(:api_sync, 10)

# Pausar fila
Oban.pause_queue(:api_sync)

# Despausar fila
Oban.resume_queue(:api_sync)
```

## 📱 Interface Mobile

O dashboard é responsivo e funciona bem em dispositivos móveis:
- Navegação otimizada para touch
- Tabelas com scroll horizontal
- Botões de ação adaptados

## 🔍 Filtros e Busca

### Filtrar por Estado:
```
- Clique nas abas: Available, Executing, etc.
- Use os filtros por data
- Busque por worker específico
```

### Filtrar por Fila:
```
- Seção "Queues" mostra jobs por fila
- Clique no nome da fila para ver jobs
- Filtre por status dentro da fila
```

## ⚠️ Troubleshooting

### Dashboard não carrega:
```
1. Verifique se o servidor está rodando
2. Confirme a URL: http://localhost:4000/dev/oban
3. Verifique se oban_web está instalado
4. Confirme a configuração no router.ex
```

### Jobs não aparecem:
```
1. Verifique se o Oban está na supervision tree
2. Confirme a configuração no config.exs
3. Execute jobs manualmente para teste
4. Verifique logs do servidor
```

### Filas não processam:
```
1. Verifique se as filas estão pausadas
2. Confirme workers estão compilando
3. Verifique dependências (HTTPoison, etc.)
4. Monitore logs de erro
```

## 🎨 Personalização

### Tema Escuro/Claro:
```
- Botão no canto superior direito
- Preferência salva no localStorage
- Aplica-se a todo o dashboard
```

### Refresh Automático:
```
- Dashboard atualiza automaticamente
- Intervalo configurável
- Pause/resume do auto-refresh
```

## 📊 Métricas Importantes

### Monitore:
```
- Throughput (jobs/segundo)
- Taxa de erro (%)
- Latência média
- Tamanho das filas
- Tempo de execução
```

### Alertas:
```
- Jobs acumulando nas filas
- Taxa de erro alta (>5%)
- Jobs com muitas tentativas
- Filas pausadas por engano
```

## 🔐 Segurança

### Produção:
```
# Mova para área protegida
scope "/admin" do
  pipe_through :admin_auth
  forward "/oban", Oban.Web.Router
end
```

### Autenticação:
```
# Adicione middleware de auth
forward "/oban", Oban.Web.Router,
  init_opts: [session: {:basic_auth, "admin", "password"}]
```

## 📈 Monitoramento Avançado

### Métricas Personalizadas:
```elixir
# Adicione telemetry
config :app, Oban,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [...]},
    {Oban.Plugins.Gossip, interval: 1_000}
  ]
```

### Integração com Observabilidade:
```elixir
# Adicione ao telemetry
:telemetry.attach_many(
  "oban-metrics",
  [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ],
  &handle_oban_event/4,
  nil
)
```

---

**🎉 Agora você tem um dashboard completo para monitorar seus jobs em tempo real!**

**Próximos passos:**
1. Acesse http://localhost:4000/dev/oban
2. Execute `mix run testar_oban_web.exs` para ver jobs
3. Explore todas as seções do dashboard
4. Configure alertas para produção 