# 🎉 Sistema de Celebrações REAIS - JuruConnect

## 📋 Visão Geral

O sistema de celebrações reais detecta automaticamente quando metas são atingidas baseado nos **dados reais da API da Jurunense** e dispara celebrações visuais e sonoras proporcionais à magnitude da conquista.

## 🎯 Tipos de Celebrações Implementadas

### 1. Meta Diária 🏪
- **Gatilho**: `perc_dia >= 100%` 
- **Fonte**: Dados de `companies[]` da API
- **Nível**: `standard`
- **Duração**: 8 segundos

### 2. Meta Horária ⏰
- **Gatilho**: `perc_hora >= 100%`
- **Fonte**: Campo `perc_hora` das lojas
- **Nível**: `minor`
- **Duração**: 5 segundos

### 3. Performance Excepcional 🔥
- **Gatilho**: `perc_dia >= 120%`
- **Fonte**: Lojas com performance 20% acima da meta
- **Nível**: `epic`
- **Duração**: 12 segundos

### 4. Vendedor Top 👑
- **Gatilho**: `percentualObjective >= 150%`
- **Fonte**: Array `saleSupervisor[]` da API
- **Nível**: `legendary`
- **Duração**: 15 segundos

### 5. Marco Mensal 🗓️
- **Gatilho**: `percentualSale >= 100%`
- **Fonte**: Dados gerais do sistema
- **Nível**: `major`
- **Duração**: 10 segundos

### 6. Venda Excepcional 🚀
- **Gatilho**: Venda ≥ 200% da meta do vendedor
- **Fonte**: Detectado em tempo real via PubSub
- **Nível**: `epic`
- **Duração**: 12 segundos

## 🎨 Níveis de Celebração

| Nível | Emoji | Cor | Partículas | Som | Efeitos Especiais |
|-------|-------|-----|------------|-----|-------------------|
| `legendary` | 👑 | Roxo/Rosa | 150 | 4 notas | Fogos de artifício |
| `epic` | 🔥 | Laranja/Vermelho | 100 | 3 notas | Fogos de artifício |
| `major` | 🎯 | Azul/Índigo | 75 | 2 notas | - |
| `standard` | ✅ | Verde/Esmeralda | 50 | 1 nota | - |
| `minor` | 📈 | Cinza | 25 | Tom baixo | - |

## 📊 Dados Utilizados da API

### Dados de Lojas (`companies[]`)
```json
{
  "nome": "Loja Centro",
  "venda_dia": 45000.50,
  "meta_dia": 40000.00,
  "perc_dia": 112.5,
  "perc_hora": 111.1
}
```

### Dados de Vendedores (`saleSupervisor[]`)
```json
{
  "sellerName": "João Silva",
  "store": "Loja Centro", 
  "saleValue": 15000.00,
  "objetivo": 10000.00,
  "percentualObjective": 150.0
}
```

## 🔧 Arquitetura Técnica

### 1. CelebrationManager (`lib/app/celebration_manager.ex`)
- Análise de dados e detecção de metas
- `process_api_data/1` - Analisa dados da API
- `process_new_sale/2` - Verifica vendas individuais
- `check_company_goals/2` - Metas por loja

### 2. DashboardDataServer
- Integração com API e trigger de celebrações
- Chama `CelebrationManager.process_api_data/1` automaticamente

### 3. Dashboard LiveView
- Recebe celebrações via `handle_info({:goal_achieved_real, data}, socket)`
- Exibe notificações com base no nível

### 4. JavaScript Hook
- Efeitos visuais por nível
- Sons personalizados
- Fogos de artifício para níveis épicos

## 🚀 Como Funciona

1. **DashboardDataServer** busca dados da API a cada 30 segundos
2. **CelebrationManager** analisa os dados recebidos
3. Se detecta meta atingida, cria estrutura de celebração
4. Faz broadcast via **PubSub** para `"dashboard:goals"`
5. **Dashboard LiveView** recebe e processa celebração
6. **JavaScript** executa efeitos visuais e sonoros

## 🎯 Exemplo de Celebração Real

Quando a API retorna:
```json
{
  "companies": [
    {
      "nome": "Loja Centro",
      "perc_dia": 105.5,
      "venda_dia": 42200.00,
      "meta_dia": 40000.00
    }
  ]
}
```

O sistema automaticamente:
1. Detecta `perc_dia >= 100%`
2. Cria celebração tipo `:daily_goal`
3. Dispara toast verde com confetti
4. Toca som de sucesso
5. Mostra "Meta Diária Atingida! - Loja Centro"

## ✨ Diferencial das Celebrações Reais

### Antes (Simulado)
- Botão "Testar Celebração" 
- Dados fictícios fixos
- Efeito genérico sempre igual

### Agora (Real)
- **Automático** baseado em dados reais da API
- **Proporcional** ao tipo e magnitude da conquista
- **Inteligente** com diferentes níveis e efeitos
- **Tempo real** via PubSub quando nova venda acontece

## 📈 Benefícios

1. **Motivação Real**: Celebra conquistas verdadeiras
2. **Feedback Imediato**: Mostra resultado em tempo real
3. **Gamificação**: Diferentes níveis criam competição saudável
4. **Transparência**: Todos veem quando metas são atingidas
5. **Engajamento**: Efeitos visuais chamam atenção para sucessos

---

**🎊 O sistema está totalmente funcional e celebra metas reais automaticamente!** 