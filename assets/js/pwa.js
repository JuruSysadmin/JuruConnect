// PWA Functionality
class PWAManager {
  constructor() {
    this.deferredPrompt = null;
    this.isInstalled = false;
    this.isStandalone = false;
    
    this.init();
  }

  init() {
    this.checkInstallStatus();
    this.setupInstallPrompt();
    this.setupUpdateNotification();
    this.setupOfflineDetection();
    this.setupAppStateDetection();
  }

  // Verificar se app está instalado
  checkInstallStatus() {
    // Verificar se está rodando como PWA
    this.isStandalone = window.matchMedia('(display-mode: standalone)').matches || 
                       window.navigator.standalone === true ||
                       document.referrer.includes('android-app://');
                       
    if (this.isStandalone) {
      this.isInstalled = true;
      console.log(' App rodando como PWA');
      this.onInstalled();
    }
  }

  // Configurar prompt de instalação
  setupInstallPrompt() {
    window.addEventListener('beforeinstallprompt', (e) => {
      console.log('💾 PWA pode ser instalado');
      e.preventDefault();
      this.deferredPrompt = e;
      this.showInstallButton();
    });

    // Detectar quando app foi instalado
    window.addEventListener('appinstalled', () => {
      console.log('✅ PWA foi instalado');
      this.deferredPrompt = null;
      this.isInstalled = true;
      this.hideInstallButton();
      this.onInstalled();
    });
  }

  // Mostrar botão de instalação
  showInstallButton() {
    // Criar botão se não existir
    if (!document.getElementById('pwa-install-btn')) {
      const installBtn = document.createElement('button');
      installBtn.id = 'pwa-install-btn';
      installBtn.innerHTML = `
        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
        </svg>
        Instalar App
      `;
      installBtn.className = 'fixed bottom-4 right-4 bg-blue-600 text-white px-4 py-2 rounded-full shadow-lg hover:bg-blue-700 transition-colors z-50 flex items-center text-sm font-medium';
      
      installBtn.addEventListener('click', () => this.promptInstall());
      document.body.appendChild(installBtn);
    }
  }

  // Esconder botão de instalação
  hideInstallButton() {
    const installBtn = document.getElementById('pwa-install-btn');
    if (installBtn) {
      installBtn.remove();
    }
  }

  // Solicitar instalação
  async promptInstall() {
    if (!this.deferredPrompt) return;

    try {
      this.deferredPrompt.prompt();
      const { outcome } = await this.deferredPrompt.userChoice;
      
      if (outcome === 'accepted') {
        console.log('✅ Usuário aceitou instalar PWA');
      } else {
        console.log('❌ Usuário rejeitou instalar PWA');
      }
      
      this.deferredPrompt = null;
    } catch (error) {
      console.error('Erro ao solicitar instalação:', error);
    }
  }

  // Notificação de atualização
  setupUpdateNotification() {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        this.showUpdateNotification();
      });
    }
  }

  // Mostrar notificação de atualização
  showUpdateNotification() {
    const notification = document.createElement('div');
    notification.id = 'pwa-update-notification';
    notification.innerHTML = `
      <div class="fixed top-4 right-4 bg-green-600 text-white px-6 py-3 rounded-lg shadow-lg z-50 max-w-sm">
        <div class="flex items-center justify-between">
          <div>
            <p class="font-medium">App atualizado!</p>
            <p class="text-sm opacity-90">Nova versão disponível</p>
          </div>
          <button onclick="this.parentElement.parentElement.remove()" class="text-white hover:text-gray-200 ml-4">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
      </div>
    `;
    
    document.body.appendChild(notification);
    
    // Remover após 5 segundos
    setTimeout(() => {
      if (document.getElementById('pwa-update-notification')) {
        notification.remove();
      }
    }, 5000);
  }

  // Detecção de conexão offline/online
  setupOfflineDetection() {
    window.addEventListener('online', () => {
      this.showConnectionStatus('Conectado!', 'green');
    });

    window.addEventListener('offline', () => {
      this.showConnectionStatus('Sem conexão', 'red');
    });
  }

  // Mostrar status da conexão
  showConnectionStatus(message, color) {
    const statusDiv = document.createElement('div');
    statusDiv.className = `fixed top-4 left-1/2 transform -translate-x-1/2 bg-${color}-600 text-white px-4 py-2 rounded-full text-sm font-medium z-50`;
    statusDiv.textContent = message;
    
    document.body.appendChild(statusDiv);
    
    setTimeout(() => {
      statusDiv.remove();
    }, 3000);
  }

  // Detectar mudanças no estado do app
  setupAppStateDetection() {
    // Detectar quando app volta do background
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && this.isInstalled) {
        console.log('📱 App voltou do background');
        this.onAppResume();
      }
    });

    // Detectar mudanças na orientação
    window.addEventListener('orientationchange', () => {
      setTimeout(() => {
        console.log('🔄 Orientação mudou para:', screen.orientation?.angle || 'desconhecido');
      }, 100);
    });
  }

  // Quando app é instalado
  onInstalled() {
    // Adicionar classe para estilos específicos de PWA
    document.body.classList.add('pwa-installed');
    
    // Analytics ou tracking (opcional)
    this.trackEvent('pwa_installed');
  }

  // Quando app volta do background
  onAppResume() {
    // Verificar atualizações, sincronizar dados, etc.
    this.checkForUpdates();
  }

  // Verificar atualizações
  async checkForUpdates() {
    if ('serviceWorker' in navigator) {
      try {
        const registration = await navigator.serviceWorker.getRegistration();
        if (registration) {
          registration.update();
        }
      } catch (error) {
        console.error('Erro ao verificar atualizações:', error);
      }
    }
  }

  // Solicitar permissões de notificação
  async requestNotificationPermission() {
    if ('Notification' in window) {
      const permission = await Notification.requestPermission();
      console.log('Permissão de notificação:', permission);
      return permission === 'granted';
    }
    return false;
  }

  // Enviar notificação local
  showNotification(title, options = {}) {
    if ('Notification' in window && Notification.permission === 'granted') {
      const notification = new Notification(title, {
        icon: '/assets/icon-192x192.png',
        badge: '/assets/icon-192x192.png',
        ...options
      });

      notification.onclick = () => {
        window.focus();
        notification.close();
      };

      return notification;
    }
  }

  // Tracking de eventos (para analytics)
  trackEvent(eventName, data = {}) {
    console.log(`📊 Event: ${eventName}`, data);
    
    // Aqui você pode integrar com Google Analytics, etc.
    // gtag('event', eventName, data);
  }

  // Compartilhar conteúdo (Web Share API)
  async share(data) {
    if (navigator.share) {
      try {
        await navigator.share(data);
        this.trackEvent('content_shared', data);
      } catch (error) {
        console.log('Compartilhamento cancelado ou falhou:', error);
      }
    } else {
      // Fallback: copiar para clipboard
      if (navigator.clipboard && data.url) {
        await navigator.clipboard.writeText(data.url);
        this.showConnectionStatus('Link copiado!', 'blue');
      }
    }
  }
}

// Inicializar PWA Manager quando DOM carregar
document.addEventListener('DOMContentLoaded', () => {
  window.pwaManager = new PWAManager();
});

// Exportar para uso global
window.PWAManager = PWAManager; 