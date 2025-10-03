# Sistema de Alertas de SLA - JuruConnect

## Visão Geral
O sistema de Alertas de SLA (Service Level Agreement) do JuruConnect monitora automaticamente o tempo de resolução das tratativas e cria alertas quando os prazos estão próximos de serem violados ou já foram violados.

## Funcionalidades Implementadas

### 🚨 **Monitoramento Automático**
- **Verificação Periódica**: Job agendado executa a cada 15 minutos
- **Cálculo Automático**: SLA baseado na categoria e prioridade da tratativa
- **Alertas Inteligentes**: Sistema de warning e critical alerts

### 📊 **Configurações de SLA por Categoria**

#### **FINANCEIRO**
- **SLA**: 24 horas
- **Warning**: 18 horas (75% do SLA)
- **Critical**: 20 horas (83% do SLA)

#### **COMERCIAL**
- **SLA**: 48 horas
- **Warning**: 36 horas (75% do SLA)
- **Critical**: 42 horas (87% do SLA)

#### **LOGISTICA**
- **SLA**: 72 horas
- **Warning**: 60 horas (83% do SLA)
- **Critical**: 66 horas (91% do SLA)

### ⚡ **Ajustes por Prioridade**

#### **URGENTE**
- SLA reduzido pela metade
- Exemplo: FINANCEIRO URGENTE = 12 horas

#### **HIGH**
- SLA reduzido em 25%
- Exemplo: COMERCIAL HIGH = 36 horas

#### **LOW**
- SLA dobrado
- Exemplo: LOGISTICA LOW = 144 horas

### 🔔 **Sistema de Notificações**

#### **Alertas de Warning**
- Notificam usuários online na tratativa
- Avisam sobre proximidade do prazo
- Não são spam (apenas um alerta por tratativa)

#### **Alertas Críticos**
- Notificam administradores
- Notificam usuários da tratativa
- Podem ser escalados para gestão

#### **Escalação Automática**
- Alertas críticos ativos há mais de 2 horas são escalados
- Notificação automática para gestores
- Marcação de escalação no sistema

### 📈 **Dashboard de Monitoramento**

#### **Métricas Principais**
- Total de alertas
- Alertas ativos
- Alertas críticos
- Taxa de conformidade SLA

#### **Ações Disponíveis**
- Resolver alertas
- Cancelar alertas
- Forçar verificação de SLA
- Atualização automática a cada 30 segundos

#### **Visualização de Alertas**
- Lista de alertas críticos
- Lista de alertas de warning
- Distribuição por categoria
- Distribuição por prioridade

## Como Usar

### **Para Administradores**

1. **Acesse o Dashboard SLA**
   ```
   http://localhost:4000/admin/sla
   ```

2. **Monitore Alertas**
   - Visualize alertas críticos que precisam de atenção
   - Monitore alertas de warning próximos de se tornar críticos
   - Acompanhe a taxa de conformidade geral

3. **Gerencie Alertas**
   - Resolva alertas quando a tratativa for resolvida
   - Cancele alertas quando não aplicáveis
   - Force verificação imediata quando necessário

### **Para Usuários**

1. **Receba Notificações**
   - Alertas aparecem como notificações desktop
   - Diferentes tipos de notificação por tipo de alerta
   - Som e ícone específicos para SLA

2. **Aja Rapidamente**
   - Alertas de warning indicam proximidade do prazo
   - Alertas críticos indicam violação iminente
   - Priorize tratativas com alertas ativos

## Configuração Técnica

### **Job Agendado**
```elixir
# Agendar verificação periódica
App.Jobs.SLACheckJob.schedule_sla_check()

# Verificação imediata
App.Jobs.SLACheckJob.schedule_immediate_sla_check()
```

### **Verificação Manual**
```elixir
# Verificar todas as tratativas ativas
App.SLAs.check_and_create_sla_alerts()

# Verificar tratativa específica
App.SLAs.check_treaty_sla(treaty)
```

### **Estatísticas**
```elixir
# Obter estatísticas completas
App.SLAs.get_sla_stats()

# Obter alertas críticos
App.SLAs.get_critical_alerts(limit)

# Obter alertas de warning
App.SLAs.get_warning_alerts(limit)
```

## Benefícios

### **Para a Empresa**
- ✅ Controle de qualidade do atendimento
- ✅ Identificação proativa de problemas
- ✅ Métricas de performance em tempo real
- ✅ Redução de violações de SLA

### **Para os Usuários**
- ✅ Alertas proativos sobre prazos
- ✅ Priorização automática de tratativas
- ✅ Notificações em tempo real
- ✅ Interface intuitiva de monitoramento

### **Para os Clientes**
- ✅ Maior conformidade com prazos
- ✅ Atendimento mais rápido
- ✅ Redução de reclamações
- ✅ Melhoria na satisfação

## Monitoramento e Manutenção

### **Logs Importantes**
- Verificação periódica de SLA
- Criação de alertas
- Envio de notificações
- Escalação de alertas

### **Métricas a Acompanhar**
- Taxa de conformidade SLA
- Tempo médio de resolução de alertas
- Número de escalações
- Distribuição de alertas por categoria

### **Manutenção Preventiva**
- Verificar logs de jobs agendados
- Monitorar performance das consultas
- Ajustar configurações conforme necessário
- Treinar equipe no uso do sistema

## Próximos Passos

### **Melhorias Futuras**
- [ ] Configuração customizável de SLA por usuário
- [ ] Integração com sistemas externos
- [ ] Relatórios automáticos por email
- [ ] Dashboard mobile responsivo
- [ ] Alertas por SMS/WhatsApp
- [ ] Integração com calendário
- [ ] SLA por horário comercial
- [ ] Alertas por feriados/finais de semana

O sistema de SLA está agora totalmente funcional e integrado ao JuruConnect! 🚀
