# Sistema de Notificações - JuruConnect

## Visão Geral

O sistema de notificações do JuruConnect permite que os usuários recebam notificações em tempo real quando:
- Recebem novas mensagens em chats
- São mencionados em mensagens usando `@username`
- Outros usuários entram ou saem do chat

## Funcionalidades

### 1. Notificações de Nova Mensagem
- **Trigger**: Quando uma nova mensagem é enviada em um chat
- **Destinatários**: Todos os usuários online no chat (exceto o remetente)
- **Tipo**: Notificação in-app + desktop (se permitido)

### 2. Notificações de Menção
- **Trigger**: Quando um usuário é mencionado usando `@username`
- **Destinatários**: Usuário mencionado
- **Tipo**: Notificação especial com destaque

### 3. Sistema de Autocomplete para Menções
- **Trigger**: Digite `@` seguido de texto para buscar usuários
- **Funcionalidade**: Lista usuários online que correspondem à busca
- **Navegação**: Use setas ↑↓ para navegar e Enter para selecionar
- **Seleção**: Clique ou pressione Enter para inserir a menção

### 4. Notificações Desktop
- **Permissão**: Requer permissão do usuário
- **Funcionalidade**: Notificações do sistema operacional
- **Interação**: Clique na notificação navega para o chat

## Arquitetura

### Backend (Elixir/Phoenix)

#### Módulos Principais:
- `App.Notifications` - Gerenciamento central de notificações
- `App.Chat` - Integração com sistema de mensagens
- `AppWeb.ChatLive` - LiveView para receber notificações

#### Fluxo de Notificação:
1. Mensagem é enviada via `App.Chat.send_message/4`
2. Sistema processa notificações via `process_message_notifications/2`
3. Notificações são enviadas via PubSub para usuários online
4. LiveView recebe e exibe notificações no frontend

### Frontend (JavaScript)

#### Componentes:
- `NotificationComponent` - Gerenciamento de notificações
- `ChatHook` - Integração com LiveView e autocomplete

#### Funcionalidades:
- Solicitação de permissão para notificações desktop
- Exibição de notificações in-app
- Reprodução de som de notificação
- Navegação para chat ao clicar na notificação
- Autocomplete para menções com navegação por teclado

## Configuração

### Configurações de Notificação (`lib/app/chat_config.ex`):
```elixir
def notification_config do
  %{
    enable_sound: true,                    # Habilitar som
    enable_desktop_notifications: true,    # Habilitar notificações desktop
    notification_timeout: 5000             # Timeout da notificação (ms)
  }
end
```

### Arquivos de Mídia:
- `priv/static/sounds/notification.mp3` - Som de notificação
- `priv/static/images/notification-icon.svg` - Ícone de notificação

## Uso

### Para Desenvolvedores:

#### Enviar Notificação Manual:
```elixir
App.Notifications.notify_new_message(message, user_id)
App.Notifications.notify_mention(message, [user_id])
```

#### Verificar Menções:
```elixir
mentioned_users = App.Notifications.extract_mentions("Olá @joao, como vai?")
```

### Para Usuários:

#### Ativar Notificações:
1. O sistema solicita permissão automaticamente
2. Clique em "Ativar" na solicitação de permissão
3. Notificações desktop serão exibidas

#### Menções com Autocomplete:
1. Digite `@` no campo de mensagem
2. Digite o nome do usuário para filtrar
3. Use setas ↑↓ para navegar na lista
4. Pressione Enter ou clique para selecionar
5. A menção será inserida automaticamente

## Personalização

### Estilo das Notificações:
As notificações in-app usam classes Tailwind CSS e podem ser personalizadas em:
- `assets/js/components/notification_component.js`

### Som de Notificação:
Substitua o arquivo `priv/static/sounds/notification.mp3` por seu próprio som.

### Ícone de Notificação:
Substitua o arquivo `priv/static/images/notification-icon.svg` por seu próprio ícone.

## Troubleshooting

### Notificações não aparecem:
1. Verifique se as permissões estão habilitadas
2. Verifique se o usuário está online no chat
3. Verifique os logs do servidor para erros

### Som não toca:
1. Verifique se o arquivo de som existe
2. Verifique se o navegador permite reprodução de áudio
3. Verifique se o volume do sistema está ligado

### Notificações desktop não funcionam:
1. Verifique se a permissão foi concedida
2. Verifique se o navegador suporta notificações
3. Verifique se o site está em HTTPS (requerido para notificações)

### Autocomplete não funciona:
1. Verifique se há usuários online no chat
2. Verifique se o JavaScript está carregado corretamente
3. Verifique se o evento `search_users` está sendo enviado

## Segurança

- Notificações só são enviadas para usuários autenticados
- Menções são validadas contra usuários existentes
- Notificações não expõem informações sensíveis
- Sistema respeita configurações de privacidade do usuário

## Performance

- Notificações são processadas de forma assíncrona
- Sistema usa PubSub para distribuição eficiente
- Notificações são limpas automaticamente após timeout
- Sistema evita spam de notificações
- Autocomplete é limitado a 5 resultados para performance