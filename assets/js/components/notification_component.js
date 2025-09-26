/**
 * Componente para gerenciar notificações do sistema
 */
class NotificationComponent {
  constructor() {
    this.notifications = [];
    this.notificationContainer = null;
    this.init();
  }

  init() {
    this.createNotificationContainer();
    this.requestPermission();
  }

  createNotificationContainer() {
    // Criar container para notificações in-app
    this.notificationContainer = document.createElement('div');
    this.notificationContainer.id = 'notification-container';
    this.notificationContainer.className = 'fixed top-4 right-4 z-50 space-y-2';
    document.body.appendChild(this.notificationContainer);
  }

  requestPermission() {
    // Removido o card de ativação de notificações
  }

  async enableNotifications() {
    if ('Notification' in window) {
      const permission = await Notification.requestPermission();
      if (permission === 'granted') {
        this.showSuccessMessage('Notificações ativadas com sucesso!');
      } else {
        this.showErrorMessage('Permissão de notificação negada');
      }
    }
  }

  showNotification(data) {
    // Criar notificação in-app
    const notification = this.createInAppNotification(data);
    this.notificationContainer.appendChild(notification);

    // Mostrar notificação desktop se permitido
    if ('Notification' in window && Notification.permission === 'granted') {
      this.showDesktopNotification(data);
    }

    // Tocar som de notificação
    this.playNotificationSound();

    // Atualizar badge do navegador
    this.updateBrowserBadge();

    // Auto-remover após 5 segundos
    setTimeout(() => {
      this.removeNotification(notification);
    }, 5000);
  }

  createInAppNotification(data) {
    const notification = document.createElement('div');
    notification.className = 'bg-white border border-gray-200 rounded-lg shadow-lg p-4 max-w-sm transform transition-all duration-300 translate-x-full';
    notification.innerHTML = `
      <div class="flex items-start space-x-3">
        <div class="flex-shrink-0">
          <div class="w-8 h-8 rounded-full bg-blue-500 flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/>
            </svg>
          </div>
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-gray-900">${data.title}</p>
          <p class="text-sm text-gray-500 mt-1">${data.body}</p>
          ${data.data && data.data.treaty_id ? `
            <button onclick="notificationComponent.navigateToChat('${data.data.treaty_id}')" class="text-xs text-blue-800 hover:text-blue-900 mt-2">
              Ver conversa
            </button>
          ` : ''}
        </div>
        <button onclick="notificationComponent.removeNotification(this.parentElement.parentElement)" class="flex-shrink-0 text-gray-400 hover:text-gray-600">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>
    `;

    // Animar entrada
    setTimeout(() => {
      notification.classList.remove('translate-x-full');
    }, 100);

    return notification;
  }

  showDesktopNotification(data) {
    const notification = new Notification(data.title, {
      body: data.body,
      icon: '/images/notification-icon.svg', // Use static icon
      tag: data.tag || 'chat-notification',
      data: data.data || {}
    });

    // Lidar com clique na notificação
    notification.onclick = () => {
      window.focus();
      notification.close();

      if (data.data && data.data.treaty_id) {
        this.navigateToChat(data.data.treaty_id);
      }
    };

    // Auto-fechar após 5 segundos
    setTimeout(() => {
      notification.close();
    }, 5000);
  }

  removeNotification(notification) {
    notification.classList.add('translate-x-full');
    setTimeout(() => {
      if (notification.parentElement) {
        notification.parentElement.removeChild(notification);
      }
    }, 300);
  }

  navigateToChat(orderId) {
    window.location.href = `/chat/${orderId}`;
  }

  playNotificationSound() {
    // Verificar se som está habilitado nas configurações
    if (!this.isSoundEnabled()) {
      return;
    }

    // Tocar som de notificação
    const soundFile = this.getNotificationSound();
    const audio = new Audio(soundFile);
    audio.volume = this.getNotificationVolume();
    
    audio.play().catch(error => {
      console.log('Erro ao tocar som de notificação:', error);
    });
  }

  /**
   * Verifica se o som de notificação está habilitado
   */
  isSoundEnabled() {
    const config = this.getNotificationConfig();
    return config.enableSound !== false; // Padrão: habilitado
  }

  /**
   * Obtém o arquivo de som da notificação
   */
  getNotificationSound() {
    const config = this.getNotificationConfig();
    return config.soundFile || '/sounds/notification.mp3';
  }

  /**
   * Obtém o volume da notificação
   */
  getNotificationVolume() {
    const config = this.getNotificationConfig();
    return config.volume || 0.5;
  }

  /**
   * Obtém as configurações de notificação do localStorage
   */
  getNotificationConfig() {
    try {
      const config = localStorage.getItem('notificationConfig');
      return config ? JSON.parse(config) : {};
    } catch (error) {
      console.error('Erro ao carregar configurações de notificação:', error);
      return {};
    }
  }

  /**
   * Salva as configurações de notificação no localStorage
   */
  saveNotificationConfig(config) {
    try {
      localStorage.setItem('notificationConfig', JSON.stringify(config));
    } catch (error) {
      console.error('Erro ao salvar configurações de notificação:', error);
    }
  }

  /**
   * Atualiza uma configuração específica
   */
  updateNotificationConfig(key, value) {
    const config = this.getNotificationConfig();
    config[key] = value;
    this.saveNotificationConfig(config);
  }

  showSuccessMessage(message) {
    this.showTemporaryMessage(message, 'bg-green-50 border-green-200 text-green-900');
  }

  showErrorMessage(message) {
    this.showTemporaryMessage(message, 'bg-red-50 border-red-200 text-red-900');
  }

  showTemporaryMessage(message, classes) {
    const messageElement = document.createElement('div');
    messageElement.className = `fixed top-4 right-4 border rounded-lg shadow-lg p-4 max-w-sm z-50 ${classes}`;
    messageElement.textContent = message;
    document.body.appendChild(messageElement);

    setTimeout(() => {
      if (messageElement.parentElement) {
        messageElement.parentElement.removeChild(messageElement);
      }
    }, 3000);
  }

  /**
   * Atualiza o badge do navegador com o contador de notificações não lidas
   */
  updateBrowserBadge(count = null) {
    // Se count não foi fornecido, buscar do servidor
    if (count === null) {
      this.fetchUnreadCount().then(unreadCount => {
        this.setBrowserBadge(unreadCount);
      });
    } else {
      this.setBrowserBadge(count);
    }
  }

  /**
   * Busca o contador de notificações não lidas do servidor
   */
  async fetchUnreadCount() {
    try {
      const response = await fetch('/api/notifications/unread-count', {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        }
      });

      if (response.ok) {
        const data = await response.json();
        return data.count || 0;
      }
    } catch (error) {
      console.error('Erro ao buscar contador de notificações:', error);
    }
    return 0;
  }

  /**
   * Define o badge do navegador
   */
  setBrowserBadge(count) {
    // Atualizar título da página com contador
    const baseTitle = document.title.replace(/^\(\d+\)\s*/, '');
    if (count > 0) {
      document.title = `(${count}) ${baseTitle}`;
    } else {
      document.title = baseTitle;
    }

    // Atualizar favicon com badge (se suportado)
    this.updateFaviconBadge(count);
  }

  /**
   * Atualiza o favicon com badge de notificação
   */
  updateFaviconBadge(count) {
    if (count === 0) {
      // Restaurar favicon original
      const originalFavicon = document.querySelector('link[rel="icon"]');
      if (originalFavicon) {
        originalFavicon.href = '/favicon.ico';
      }
      return;
    }

    // Criar canvas para gerar favicon com badge
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    canvas.width = 32;
    canvas.height = 32;

    // Desenhar ícone base (círculo azul)
    ctx.fillStyle = '#3B82F6';
    ctx.beginPath();
    ctx.arc(16, 16, 16, 0, 2 * Math.PI);
    ctx.fill();

    // Desenhar contador
    ctx.fillStyle = '#FFFFFF';
    ctx.font = 'bold 12px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    
    const countText = count > 99 ? '99+' : count.toString();
    ctx.fillText(countText, 16, 16);

    // Converter para data URL e atualizar favicon
    const dataURL = canvas.toDataURL('image/png');
    let favicon = document.querySelector('link[rel="icon"]');
    
    if (!favicon) {
      favicon = document.createElement('link');
      favicon.rel = 'icon';
      document.head.appendChild(favicon);
    }
    
    favicon.href = dataURL;
  }

  /**
   * Limpa o badge do navegador
   */
  clearBrowserBadge() {
    this.setBrowserBadge(0);
  }
}

// Criar instância global
window.notificationComponent = new NotificationComponent();

export default NotificationComponent;