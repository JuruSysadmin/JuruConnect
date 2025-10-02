# Resumo dos Testes TDD para Dashboard Administrativo

## Objetivo
Compreender como são feitos os cálculos das métricas do dashboard administrativo de tratativas (http://localhost:4000/admin/dashboard) usando Test-Driven Development.

## Estrutura dos Cálculos

### 1. Total de Trativas
- **Função**: `get_total_treaties_count/0`
- **Cálculo**: `from(t in Treaty, select: count()) |> Repo.one() || 0`
- **Finalidade**: Conta todas as tratativas no sistema

### 2. Trativas Ativas
- **Função**: `get_active_treaties_count/0`
- **Cálculo**: `from(t in Treaty, where: t.status == "active", select: count()) |> Repo.one() || 0`
- **Finalidade**: Conta tratativas com status "active"

### 3. Trativas Encerradas
- **Função**: `get_closed_treaties_count/0`
- **Cálculo**: `from(t in Treaty, where: t.status == "closed", select:<count()) |> Repo.one() || 0`
``` - **Finalidade**: Conta tratativas com status "closed"

### 4. Tempo Médio de Resolução
- **Função**: `get_average_resolution_time/0`
- **Cálculo**: Calcula o tempo entre `inserted_at` e `closed_at` em segundos, converte para horas usando `EXTRACT(EPOCH FROM (closed_at - inserted_at))`
- **Finalidade**: Tempo médio para resolver tratativas

### 5. Taxa de Reabertura
- **Função**: `get_reopen_rate/0`
- **Cálculo**: `(COUNT(DISTINCT reopened_treaties) / total_closed_treaties) * 100`
- **Finalidade**: Porcentagem de tratativas que foram reabertas após serem fechadas

### 6. Motivos Maiori Comuns de Fechamento
- **Função**: `get_most_common_close_reasons/1`
- **Cálculo**: Agrupa por `close_reason`, conta frequência, ordena desc
- **Finalidade**: Lista motivos ("resolved", "cancelled", "duplicate", etc.) ordenados por frequência

### 7. Distribuição por Status
- **Função**: `get_treaties_by_status/0`
- **Cálculo**: Agrupa por `status` e conta quantas tratativas em cada status
- **Finalidade**: Distribuição geral de tratativas por status

### 8. Atividades Recentes
- **Função**: `get_recent_activities/1`
- **Cálculo**: Últimas atividades das `treaty_activities` ordenadas por `activity_at` desc
- **Finalidade**: Timeline de atividades recentes no sistema

## Arquitetura dos Testes

Os testes seguem padrão **AAA** (Arrange-Act-Assert):

### Setup
- Criação de lojas (`stores`) com UUIDs válidos
- Criação de usuários (`users`) associados às lojas
- Mock de dados de tratativas com diferentes estados e timestamps

### Arrange
- Dados de teste com cenários específicos
- Simulação de diferentes durações de resolução
- Atividades de reabertura para testar taxa

### Act
- Chamadas às funções de cálculo das métricas
- Execução das consultas de agregação

### Assert  
- Verificação de valores calculados
- Validação de contagens e percentuais
- Teste de casos extremos (zero tratativas, etc.)

## Benefícios do TDD

1. **Documentação viva**: Os testes servem como documentação dos cálculos
2. **Validação contínua**: Garante que mudanças não quebrem cálculos existentes
3. **Regressão**: Detecta problemas quando métricas mudam inesperadamente
4. **Cobertura**: Testa diferentes cenários de dados

## Implementação Real

O código de produção se encontra em:
- `lib/app/treaties.ex` - Módulo principal com funções de cálculo
- `lib/app_web/live/admin_dashboard_live.ex` - LiveView que apresenta as métricas
- `lib/app_web/live/admin_dashboard_live.html.heex` - Template HTML

## Conclusão

Os cálculos das métricas são baseados em agregações SQL simples mas eficazes que fornecem insights importantes sobre o desempenho do sistema de tratativas. O TDD garante que essas métricas sejam confiáveis e mantidas consistentes conforme a evolução do sistema.
