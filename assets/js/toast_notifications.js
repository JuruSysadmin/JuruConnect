// Toast Notification System
export const ToastNotificationHook = {
  mounted() {
    this.toastContainer = this.createToastContainer();
    document.body.appendChild(this.toastContainer);
    
    // Listen for toast events
    this.handleEvent("show-toast", (data) => {
      this.showToast(data);
    });
  },

  destroyed() {
    if (this.toastContainer && this.toastContainer.parentNode) {
      this.toastContainer.parentNode.removeChild(this.toastContainer);
    }
  },

  createToastContainer() {
    const container = document.createElement('div');
    container.id = 'toast-container';
    container.className = 'fixed top-4 right-4 z-50 space-y-2';
    container.style.pointerEvents = 'none';
    return container;
  },

  showToast(data) {
    const toast = this.createToast(data);
    this.toastContainer.appendChild(toast);
    
    // Animate in
    setTimeout(() => {
      toast.classList.add('toast-enter');
    }, 10);
    
    // Auto remove after delay
    setTimeout(() => {
      this.removeToast(toast);
    }, data.duration || 5000);
  },

  createToast(data) {
    const toast = document.createElement('div');
    toast.className = `toast-notification ${data.type || 'info'} ${data.position || 'top-right'}`;
    toast.style.pointerEvents = 'auto';
    
    const icon = this.getIcon(data.type);
    const colorClasses = this.getColorClasses(data.type);
    
    toast.innerHTML = `
      <div class="flex items-start space-x-3 p-4 bg-white rounded-lg shadow-lg border-l-4 ${colorClasses.border} max-w-sm">
        <div class="flex-shrink-0">
          <div class="w-6 h-6 ${colorClasses.iconBg} rounded-full flex items-center justify-center">
            ${icon}
          </div>
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium ${colorClasses.text}">${data.title || 'Notificação'}</p>
          ${data.message ? `<p class="text-sm text-gray-600 mt-1">${data.message}</p>` : ''}
        </div>
        <button class="flex-shrink-0 ml-2 text-gray-400 hover:text-gray-600 transition-colors" onclick="this.parentElement.parentElement.remove()">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `;
    
    return toast;
  },

  getIcon(type) {
    const icons = {
      success: '<svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>',
      error: '<svg class="w-4 h-4 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>',
      warning: '<svg class="w-4 h-4 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L4.268 19.5c-.77.833.192 2.5 1.732 2.5z"></path></svg>',
      info: '<svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>'
    };
    return icons[type] || icons.info;
  },

  getColorClasses(type) {
    const classes = {
      success: {
        border: 'border-green-500',
        iconBg: 'bg-green-100',
        text: 'text-green-800'
      },
      error: {
        border: 'border-red-500',
        iconBg: 'bg-red-100',
        text: 'text-red-800'
      },
      warning: {
        border: 'border-yellow-500',
        iconBg: 'bg-yellow-100',
        text: 'text-yellow-800'
      },
      info: {
        border: 'border-blue-500',
        iconBg: 'bg-blue-100',
        text: 'text-blue-800'
      }
    };
    return classes[type] || classes.info;
  },

  removeToast(toast) {
    toast.classList.add('toast-exit');
    setTimeout(() => {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast);
      }
    }, 300);
  }
};

// Loading States Hook
export const LoadingStatesHook = {
  mounted() {
    this.loadingOverlay = this.createLoadingOverlay();
    document.body.appendChild(this.loadingOverlay);
    
    // Listen for loading events
    this.handleEvent("show-loading", (data) => {
      this.showLoading(data);
    });
    
    this.handleEvent("hide-loading", () => {
      this.hideLoading();
    });
  },

  destroyed() {
    if (this.loadingOverlay && this.loadingOverlay.parentNode) {
      this.loadingOverlay.parentNode.removeChild(this.loadingOverlay);
    }
  },

  createLoadingOverlay() {
    const overlay = document.createElement('div');
    overlay.id = 'loading-overlay';
    overlay.className = 'fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center';
    overlay.style.display = 'none';
    return overlay;
  },

  showLoading(data) {
    const message = data.message || 'Carregando...';
    const type = data.type || 'spinner';
    
    this.loadingOverlay.innerHTML = `
      <div class="bg-white rounded-xl p-6 shadow-2xl max-w-sm mx-4">
        <div class="flex items-center space-x-3">
          <div class="flex-shrink-0">
            ${this.getLoadingIcon(type)}
          </div>
          <div class="flex-1">
            <p class="text-sm font-medium text-gray-900">${message}</p>
            ${data.subtitle ? `<p class="text-xs text-gray-600 mt-1">${data.subtitle}</p>` : ''}
          </div>
        </div>
        ${data.progress !== undefined ? this.createProgressBar(data.progress) : ''}
      </div>
    `;
    
    this.loadingOverlay.style.display = 'flex';
  },

  hideLoading() {
    this.loadingOverlay.style.display = 'none';
  },

  getLoadingIcon(type) {
    const icons = {
      spinner: '<div class="w-6 h-6 border-2 border-blue-600 border-t-transparent rounded-full animate-spin"></div>',
      dots: '<div class="flex space-x-1"><div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce"></div><div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style="animation-delay: 0.1s"></div><div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style="animation-delay: 0.2s"></div></div>',
      pulse: '<div class="w-6 h-6 bg-blue-600 rounded-full animate-pulse"></div>'
    };
    return icons[type] || icons.spinner;
  },

  createProgressBar(progress) {
    return `
      <div class="mt-3">
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" style="width: ${progress}%"></div>
        </div>
        <p class="text-xs text-gray-600 mt-1 text-center">${progress}%</p>
      </div>
    `;
  }
};
