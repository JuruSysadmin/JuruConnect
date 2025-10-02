# Integração Gemini AI no Chat

## ✅ Status da Integração

A integração está **funcionando perfeitamente**! 

### Últimas atualizações:
- ✅ Serviço Gemini funcionando sem erros
- ✅ **NOVA FUNCIONALIDADE**: Integração com API de pedidos!
- ✅ Comandos `/ai` e `/pergunta` processados corretamente  
- ✅ Task assíncrono sem crashes do LiveView
- ✅ Mensagens IA salvas no banco de dados
- ✅ Broadcast via PubSub funcionando
- ✅ Tratamento de erros da API Gemini
- ✅ **Consulta automática de etapas dos pedidos via API externa**

## Configuração

1. **Definir a chave da API** como variável de ambiente:
```bash
export GEMINI_API_KEY="AIzaSyBgeJuyCTTobJw7TVbAnLtfb4gUdADoRsI"
```

2. **Reiniciar o servidor** para aplicar as configurações:
```bash
mix phx.server
```

## Como Usar

No chat, digite um dos comandos seguido de sua pergunta:

### Comandos Disponíveis

- `/ai [sua pergunta]` - Faz uma pergunta geral ao assistente IA
- `/pergunta [sua pergunta]` - Alternativa ao comando `/ai`

## 🆕 Nova Funcionalidade: Consulta de Pedidos

**A IA agora consulta dados específicos dos pedidos automaticamente!**

Quando você fizer uma pergunta em uma tratativa que contenha um número de pedido, a IA automaticamente:

1. **Extrai o número do pedido** do treaty_id ou código da tratativa
2. **Consulta a API** `http://10.1.119.91:8066/api/v1/orders/leadtime/{número_pedido}`
3. **Formata os dados** para criar contexto específico
4. **Responde com informações detalhadas** sobre etapas, datas e funcionários

### 🎯 Exemplos de Perguntas Inteligentes sobre Pedidos:

- **"Qual etapa meu pedido está?"**
  - Resposta: Pedido 153068529 está na etapa "Entrega Realizada" (última etapa)

- **"Quando começou a separação?"** 
  - Resposta: Separação iniciou em 18/09/2025 16:59 por PAULINO ANTONIO DA SILVEIRA NETO

- **"Quem fez a conferência?"**
  - Resposta: Conferência realizada por MICHEL DE JESUS SERRAO FERREIRA em 18/09/2025

- **"Qual o tempo total do pedido?"**
  - Resposta: Análise completa com todas as etapas e prazos

- **"Quantas etapas já foram concluídas?"**
  - Resposta: 9 etapas concluídas desde a venda até entrega

### 🔍 Como Funciona a Extração do Pedido:

A IA tenta extrair números de 9 dígitos de:
1. **treaty_id** diretamente (ex: `TRT589316` → pedido `153068529`)
2. **código da tratativa** no banco de dados
3. Qualquer número de 9 dígitos no identificador

### 📊 Dados que a API Retorna:

```json
{
  "success": true,
  "data": [
    {
      "etapa": 0,
      "descricaoEtapa": "Venda Realizada",
      "data": "2025-08-21T17:33:00.000Z",
      "nomeFuncionario": "ELIVONE MARIA GOMES VIEIRA"
    }
    // ... mais etapas
  ]
}
```

### Exemplos de Uso Geral:

```
/ai Como funciona a inteligência artificial?
/pergunta Qual é a diferença entre machine learning e deep learning?
/ai Como criar um chatbot?
/pergunta Qual é a melhor linguagem para desenvolvimento web?
```

## Funcionalidades

- ✅ Detecção automática de comandos de IA
- ✅ **Consulta automática de API de pedidos (NOVO!)**
- ✅ Processamento assíncrono (não bloqueia o chat)
- ✅ Respostas em português brasileiro
- ✅ Limitação de caracteres nas respóstas (1500 chars máx)
- ✅ Tratamento de erros da API Gemini
- ✅ Contexto adaptável (geral, com dados de pedido específicos)
- ✅ **Formatação inteligente de datas e etapas**
- ✅ **Respostas específicas baseadas em dados reais**

## Limitações

- Perguntas limitadas a 1000 caracteres
- Respostas limitadas a 1500 caracteres
- Processamento assíncrono (pode levar alguns segundos)
- Requer conexão com internet
- **API de pedidos deve estar online** (`http://10.1.119.91:8066`)
- **Funciona apenas com números de pedido de 9 dígitos**

## Arquitetura

- `App.Services.GeminiService` - Serviço principal para API do Gemini
  - `determine_context/1` - Extrai número do pedido e consulta API
  - `fetch_pedido_data/1` - Faz requisição HTTP para API de pedidos
  - `format_pedido_data/1` - Formata dados para contexto da IA
- `App.Chat.send_message/4` - Processamento de comandos no chat
- Mensagens tipo `ai_response` e `ai_error` no sistema

## 🔧 Endpoints Utilizados

- **Gemini API**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent`
- **API de Pedidos**: `http://10.1.119.91:8066/api/v1/orders/leadtime/{numero_pedido}`

## 📝 Exemplo de Resposta Completa

**Pergunta**: `/ai Qual etapa meu pedido está?`

**Contexto gerado**:
```
DADOS DO PEDIDO 153068529:
Etapa atual: Entrega Realizada

Etapas percorridas:
  0. Venda Realizada - 2025-08-21 14:33 (ELIVONE MARIA GOMES VIEIRA)
  2. Montagem Carga - 2025-09-17 00:12 (MILENA DE ANDRADE ALIEVI)
  3. Início Separação - 2025-09-18 16:59 (PAULINO ANTONIO DA SILVEIRA NETO)
  ...
```

**Resposta gerada**: Informação específica sobre o status atual e histórico completo.