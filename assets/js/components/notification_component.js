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
          ${data.data && data.data.order_id ? `
            <button onclick="notificationComponent.navigateToChat('${data.data.order_id}')" class="text-xs text-blue-800 hover:text-blue-900 mt-2">
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

      if (data.data && data.data.order_id) {
        this.navigateToChat(data.data.order_id);
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
    const audio = new Audio('/sounds/notification.mp3');
    audio.volume = 0.5;
    audio.play().catch(error => {
      console.log('Could not play notification sound:', error);
    });
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
}

// Criar instância global
window.notificationComponent = new NotificationComponent();

export default NotificationComponent;