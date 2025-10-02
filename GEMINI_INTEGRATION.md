# Integração Gemini AI no Chat

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

### Exemplos de Uso

```
/ai Como funciona a inteligência artificial?
/pergunta Qual é a diferença entre machine learning e deep learning?
/ai Como criar um chatbot?
/pergunta Qual é a melhor linguagem para desenvolvimento web?
```

## Funcionalidades

- ✅ Detecção automática de comandos de IA
- ✅ Processamento assíncrono (não bloqueia o chat)
- ✅ Respostas em português brasileiro
- ✅ Limitação de caracteres nas respostas (1500 chars máx)
- ✅ Tratamento de erros da API
- ✅ Contexto adaptável (geral, suporte, vendas)

## Limitações

- Perguntas limitadas a 1000 caracteres
- Respostas limitadas a 1500 caracteres
- Processamento assíncrono (pode levar alguns segundos)
- Requer conexão com internet

## Arquitetura

- `App.Services.GeminiService` - Serviço principal para API do Gemini
- `App.Chat.Room` - Processamento de comandos no GenServer do chat
- Mensagens tipo `ai_response` e `ai_error` no sistema
