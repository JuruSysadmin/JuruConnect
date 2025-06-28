# Monitoramento do Oban - Resumo Prático

## Opções Disponíveis

### 1. **Monitor via Linha de Comando (Disponível Agora)**

Execute o script que criei:
```bash
mix run monitor_oban.exs
```

**Mostra:**
- Status das filas (pendentes, executando, falhados)
- Estatísticas das últimas 24h
- Atividade recente
- Verificação de saúde

### 2. **Dashboard Web do Oban (Recomendado)**

**Para instalar:**
```bash
# Adicionar ao mix.exs
{:oban_web, "~> 2.10"}

# Instalar
mix deps.get
```

**Acesso:**
- Desenvolvimento: `http://localhost:4000/dev/oban`
- Produção: Com autenticação

### 3. **Comandos no IEx**

```elixir
# Iniciar IEx
iex -S mix

# Ver jobs por estado
import Ecto.Query
alias App.Repo

# Jobs pendentes
from(j in Oban.Job, where: j.state == "available") |> Repo.all()

# Jobs falhados
from(j in Oban.Job, where: j.state == "retryable") |> Repo.all()

# Jobs executando
from(j in Oban.Job, where: j.state == "executing") |> Repo.all()

# Pausar fila
Oban.pause_queue(queue: :api_sync)

# Despausar fila  
Oban.resume_queue(queue: :api_sync)
```

### 4. **Monitoramento de Logs**

```bash
# Ver logs em tempo real
tail -f log/dev.log | grep -i oban

# Filtrar apenas erros
tail -f log/dev.log | grep -i "error.*oban"
```

## Comandos Rápidos

### **Verificar Status**
```bash
mix run monitor_oban.exs
```

### **Ver Jobs Específicos**
```bash
# Jobs do SupervisorDataWorker
mix run -e "
import Ecto.Query
alias App.Repo
from(j in Oban.Job, where: like(j.worker, \"%SupervisorDataWorker%\")) 
|> Repo.all() 
|> IO.inspect()
"
```

### **Limpar Jobs Antigos**
```bash
# Jobs completados há mais de 7 dias
mix run -e "
import Ecto.Query
alias App.Repo
week_ago = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60)
from(j in Oban.Job, 
  where: j.state == \"completed\" and j.completed_at < ^week_ago) 
|> Repo.delete_all()
"
```

### **Estatísticas Rápidas**
```bash
mix run -e "
import Ecto.Query
alias App.Repo
stats = from(j in Oban.Job, group_by: j.state, select: {j.state, count()}) |> Repo.all()
IO.inspect(stats, label: \"Jobs por estado\")
"
```

## Para Produção

### **Alertas Simples**
```bash
# Criar script de alerta
# check_oban.sh
#!/bin/bash
FAILED_JOBS=$(mix run -e "
import Ecto.Query
alias App.Repo
count = from(j in Oban.Job, where: j.state == \"retryable\", select: count()) |> Repo.one()
IO.puts(count)
")

if [ "$FAILED_JOBS" -gt 10 ]; then
  echo "ALERTA: $FAILED_JOBS jobs falharam!"
  # Enviar email/Slack/etc
fi
```

### **Cron para Monitoramento**
```bash
# Adicionar ao crontab
# */15 * * * * cd /path/to/app && mix run monitor_oban.exs >> /var/log/oban_monitor.log
```

## Próximos Passos

1. **Use agora**: `mix run monitor_oban.exs`
2. **Para dashboard visual**: Instale `oban_web`
3. **Para produção**: Configure alertas automáticos
4. **Para análise**: Use comandos IEx específicos

## Exemplo de Output do Monitor

```
=== MONITOR OBAN ===
Coletado em: 2024-12-16 15:30:00Z

--- STATUS DAS FILAS ---
Available (aguardando):  5
Executing (executando):  2
Completed (concluídos):  1,245
Retryable (para retry):  0
Cancelled (cancelados):  0
Discarded (descartados): 3

--- ESTATÍSTICAS (ÚLTIMAS 24H) ---
Total processados: 156
Taxa de sucesso:   98.1%
Jobs por hora:     6.5

Workers mais ativos:
  SupervisorDataWorker: 24 jobs
  EmailWorker: 12 jobs

--- ATIVIDADE RECENTE ---
  ✅ SupervisorDataWorker - 15m atrás
  ✅ SupervisorDataWorker - 45m atrás
  🔄 EmailWorker - 1h atrás

--- VERIFICAÇÃO DE SAÚDE ---
✅ Oban funcionando normalmente
```

Com essas ferramentas você tem visibilidade completa do Oban! 