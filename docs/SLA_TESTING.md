# Teste do Sistema de SLA

## Como Testar o Sistema de Alertas de SLA

### 1. **Criar uma Tratativa de Teste**

```elixir
# No console do Phoenix (iex -S mix phx.server)
alias App.Treaties
alias App.Accounts

# Criar usuário de teste se não existir
{:ok, user} = App.Accounts.create_user(%{
  username: "teste_sla",
  name: "Usuário Teste SLA",
  role: "user",
  password: "123456"
})

# Criar tratativa FINANCEIRO URGENTE (SLA: 12 horas)
{:ok, treaty} = Treaties.create_treaty(%{
  title: "Teste SLA Financeiro Urgente",
  description: "Tratativa para testar alertas de SLA",
  category: "FINANCEIRO",
  priority: "urgent",
  created_by: user.id,
  store_id: user.id
})

IO.puts("Tratativa criada: #{treaty.treaty_code}")
```

### 2. **Simular Passagem de Tempo**

```elixir
# Atualizar timestamp para simular tratativa antiga
import Ecto.Query
alias App.Repo

# Simular tratativa criada há 10 horas (dentro do warning)
ten_hours_ago = DateTime.add(DateTime.utc_now(), -10 * 60 * 60, :second)

Repo.update_all(
  from(t in App.Treaties.Treaty, where: t.id == ^treaty.id),
  set: [inserted_at: ten_hours_ago]
)

IO.puts("Tratativa atualizada para 10 horas atrás")
```

### 3. **Executar Verificação de SLA**

```elixir
# Verificar SLA da tratativa específica
App.SLAs.check_treaty_sla(treaty)

# Ou verificar todas as tratativas
App.SLAs.check_and_create_sla_alerts()

IO.puts("Verificação de SLA executada")
```

### 4. **Verificar Alertas Criados**

```elixir
# Listar alertas ativos
alerts = App.SLAs.list_sla_alerts(status: "active")

IO.puts("Alertas ativos: #{length(alerts)}")
Enum.each(alerts, fn alert ->
  IO.puts("- #{alert.treaty.treaty_code}: #{alert.alert_type} (#{alert.category})")
end)
```

### 5. **Verificar Estatísticas**

```elixir
# Obter estatísticas de SLA
stats = App.SLAs.get_sla_stats()

IO.puts("=== Estatísticas SLA ===")
IO.puts("Total de alertas: #{stats.total_alerts}")
IO.puts("Alertas ativos: #{stats.active_alerts}")
IO.puts("Alertas críticos: #{stats.critical_alerts}")
IO.puts("Alertas de warning: #{stats.warning_alerts}")
IO.puts("Taxa de conformidade: #{stats.sla_compliance_rate}%")
```

### 6. **Testar Job Agendado**

```elixir
# Agendar job de verificação
App.Jobs.SLACheckJob.schedule_immediate_sla_check()

IO.puts("Job de verificação agendado")
```

### 7. **Acessar Dashboard**

1. Acesse: `http://localhost:4000/admin/sla`
2. Verifique se os alertas aparecem
3. Teste as ações de resolver/cancelar
4. Monitore a atualização automática

### 8. **Testar Notificações**

```elixir
# Simular notificação de alerta crítico
alert = List.first(App.SLAs.get_critical_alerts(1))

if alert do
  # Notificar administradores
  admins = App.Accounts.get_users_by_role("admin")
  Enum.each(admins, fn admin ->
    App.Notifications.send_desktop_notification(admin, %{
      id: "test-sla-#{alert.id}",
      text: "TESTE: Alerta crítico para #{alert.treaty.treaty_code}",
      sender_name: "Sistema SLA",
      treaty_id: alert.treaty_id,
      tipo: "sla_alert"
    }, :sla_critical)
  end)
  
  IO.puts("Notificações de teste enviadas")
end
```

### 9. **Limpar Dados de Teste**

```elixir
# Remover alertas de teste
Repo.delete_all(from(a in App.SLAs.SLAAlert, where: a.treaty_id == ^treaty.id))

# Remover tratativa de teste
Repo.delete_all(from(t in App.Treaties.Treaty, where: t.id == ^treaty.id))

IO.puts("Dados de teste removidos")
```

## Cenários de Teste

### **Cenário 1: Warning Alert**
- Tratativa FINANCEIRO NORMAL criada há 18 horas
- Deve gerar alerta de warning

### **Cenário 2: Critical Alert**
- Tratativa COMERCIAL HIGH criada há 32 horas
- Deve gerar alerta crítico

### **Cenário 3: Escalação**
- Alerta crítico ativo há mais de 2 horas
- Deve ser escalado para gestão

### **Cenário 4: Resolução**
- Resolver alerta quando tratativa for fechada
- Deve marcar alerta como resolvido

## Verificações Importantes

✅ **Alertas são criados corretamente**
✅ **Notificações são enviadas**
✅ **Dashboard mostra dados atualizados**
✅ **Jobs agendados funcionam**
✅ **Escalação automática funciona**
✅ **Estatísticas são calculadas corretamente**
✅ **Interface é responsiva**
✅ **Performance é adequada**

## Troubleshooting

### **Problema: Alertas não são criados**
- Verificar se tratativa está com status "active"
- Verificar se timestamps estão corretos
- Verificar logs do job agendado

### **Problema: Notificações não aparecem**
- Verificar se usuário está online
- Verificar configuração de notificações
- Verificar logs de notificação

### **Problema: Dashboard não atualiza**
- Verificar conexão WebSocket
- Verificar logs do LiveView
- Verificar se job está executando

O sistema de SLA está pronto para uso em produção! 🎉
