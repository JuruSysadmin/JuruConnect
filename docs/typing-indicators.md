# Sistema de Indicadores de Digitação

## Visão Geral

O sistema de indicadores de digitação permite aos usuários visualizar em tempo real quando outros participantes estão digitando mensagens no chat.

## Componentes Implementados

### 1. Eventos de Frontend

- `typing_start`: Disparado quando o usuário inicia digitação
- `typing_stop`: Disparado quando o usuário para de digitar
- Debounce de 300ms para evitar spam de eventos

### 2. Gerenciamento de Estado

- `typing_users`: MapSet contendo usuários que estão digitando
- `is_typing`: Boolean indicando se o usuário atual está digitando
- Timeout automático de 3 segundos configurável

### 3. Comunicação via PubSub

- Broadcasting de eventos de digitação para todos os participantes
- Eventos: `{:typing_start, user_name}` e `{:typing_stop, user_name}`

### 4. Interface Visual

- Indicador animado com três pontos pulsantes
- Texto formatado baseado no número de usuários digitando
- Posicionamento consistente com o design do chat

## Configuração

### Timeout de Digitação

Configurável em `App.ChatConfig`:

```elixir
def typing_timeout, do: 3000  # 3 segundos
```

### Debounce de Input

Configurado no template HTML:

```elixir
phx-debounce="300"  # 300ms
```

## Comportamentos

### Início de Digitação

1. Usuário digita no campo de mensagem
2. Evento `typing_start` é disparado
3. Broadcast via PubSub para outros usuários
4. Timer de timeout é iniciado

### Parada de Digitação

1. Usuário para de digitar (blur do input)
2. Campo de mensagem fica vazio
3. Mensagem é enviada
4. Timeout automático é atingido

### Formatação de Usuários

- 1 usuário: "João digitando..."
- 2 usuários: "João e Maria digitando..."
- 3+ usuários: "3 usuários digitando..."

## Otimizações Implementadas

- Timeout automático previne indicadores órfãos
- Debounce evita eventos excessivos
- MapSet para gerenciamento eficiente de usuários
- Cleanup automático ao enviar mensagens
- Verificação de usuário próprio para evitar auto-indicação

## Performance

- Overhead mínimo de rede
- Estado local otimizado
- Cleanup automático de memória
- Eventos assíncronos não bloqueantes 