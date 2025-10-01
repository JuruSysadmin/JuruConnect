// Composite Chat Hook - Combines all chat-related functionality
import { KeyboardShortcutsHook } from '../keyboard_shortcuts.js';
import { ToastNotificationHook } from '../toast_notifications.js';
import { LoadingStatesHook } from '../toast_notifications.js';

const ChatCompositeHook = {
  mounted() {
    console.log('ChatCompositeHook mounted - initializing all chat functionality');
    
    // Initialize ChatHook functionality
    this.initializeChat();
    
    // Initialize KeyboardShortcutsHook functionality
    this.initializeKeyboardShortcuts();
    
    // Initialize ToastNotificationHook functionality
    this.initializeToastNotifications();
    
    // Initialize LoadingStatesHook functionality
    this.initializeLoadingStates();
  },

  updated() {
    // Handle updates for chat functionality
    this.handleChatUpdate();
  },

  destroyed() {
    // Cleanup all functionality
    this.cleanup();
  },

  // ChatHook functionality
  initializeChat() {
    console.log('ChatHook functionality initialized');
    this.el = this.el; // Ensure element reference
    this.scrollToBottom(false);
    this.setupEventListeners();
    this.setupTypingDetection();
  },

  handleChatUpdate() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      const wasAtBottom = this.isAtBottom(messagesContainer);
      if (wasAtBottom) {
        this.scrollToBottom(true);
      }
    }
  },

  setupEventListeners() {
    // Handle scroll to bottom events
    this.handleEvent("scroll-to-bottom", () => {
      this.scrollToBottom();
    });

    // Setup scroll detection for auto-scroll behavior
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      messagesContainer.addEventListener('scroll', () => {
        this.handleScroll();
      });
    }
  },

  setupTypingDetection() {
    const messageInput = this.el.querySelector('#message-input');
    if (messageInput) {
      let typingTimer;
      
      messageInput.addEventListener('input', () => {
        clearTimeout(typingTimer);
        this.pushEvent("typing", {});
        
        typingTimer = setTimeout(() => {
          this.pushEvent("stop_typing", {});
        }, 1000);
      });
    }
  },

  scrollToBottom(smooth = true) {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      if (smooth) {
        messagesContainer.scrollTo({
          top: messagesContainer.scrollHeight,
          behavior: 'smooth'
        });
      } else {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }
  },

  isAtBottom(container) {
    const threshold = 100;
    return container.scrollTop + container.clientHeight >= container.scrollHeight - threshold;
  },

  handleScroll() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      const isAtBottom = this.isAtBottom(messagesContainer);
      const scrollButton = this.el.querySelector('#scroll-to-bottom-btn');
      
      if (scrollButton) {
        if (isAtBottom) {
          scrollButton.classList.add('hidden');
        } else {
          scrollButton.classList.remove('hidden');
        }
      }
    }
  },

  // KeyboardShortcutsHook functionality
  initializeKeyboardShortcuts() {
    console.log('KeyboardShortcutsHook functionality initialized');
    this.handleKeydown = this.handleKeydown.bind(this);
    document.addEventListener('keydown', this.handleKeydown);
    
    // Show shortcuts help on first visit
    this.showShortcutsHelp();
  },

  handleKeydown(event) {
    // Only handle shortcuts when not typing in input fields
    if (this.isTypingInInput(event.target)) {
      return;
    }

    switch (event.key) {
      case '/':
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault();
          this.focusSearchInput();
        }
        break;
      case 'Escape':
        this.clearSearch();
        break;
      case 'ArrowUp':
      case 'ArrowDown':
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault();
          this.navigateMessages(event.key);
        }
        break;
      case '?':
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault();
          this.showShortcutsHelp();
        }
        break;
    }
  },

  isTypingInInput(element) {
    const inputTypes = ['INPUT', 'TEXTAREA', 'SELECT'];
    return inputTypes.includes(element.tagName) || element.contentEditable === 'true';
  },

  focusSearchInput() {
    const searchInput = this.el.querySelector('#treaty-search-input');
    if (searchInput) {
      searchInput.focus();
      searchInput.select();
    }
  },

  clearSearch() {
    const searchInput = this.el.querySelector('#treaty-search-input');
    if (searchInput) {
      searchInput.value = '';
      searchInput.blur();
      this.pushEvent("clear_search", {});
    }
  },

  navigateMessages(direction) {
    const messages = this.el.querySelectorAll('.message-item');
    const currentFocused = document.activeElement;
    const currentIndex = Array.from(messages).indexOf(currentFocused);
    
    let nextIndex;
    if (direction === 'ArrowUp') {
      nextIndex = currentIndex > 0 ? currentIndex - 1 : messages.length - 1;
    } else {
      nextIndex = currentIndex < messages.length - 1 ? currentIndex + 1 : 0;
    }

    if (messages[nextIndex]) {
      messages[nextIndex].focus();
    }
  },

  showShortcutsHelp() {
    // Implementation for showing shortcuts help
    console.log('Showing keyboard shortcuts help');
  },

  // ToastNotificationHook functionality
  initializeToastNotifications() {
    console.log('ToastNotificationHook functionality initialized');
    this.toastContainer = this.createToastContainer();
    document.body.appendChild(this.toastContainer);
    
    // Listen for toast events
    this.handleEvent("show-toast", (data) => {
      this.showToast(data);
    });
  },

  createToastContainer() {
    const container = document.createElement('div');
    container.id = 'toast-container';
    container.className = 'fixed top-4 right-4 z-50 space-y-2';
    return container;
  },

  showToast(data) {
    const toast = this.createToast(data);
    this.toastContainer.appendChild(toast);
    
    // Auto remove after duration
    setTimeout(() => {
      this.removeToast(toast);
    }, data.duration || 5000);
  },

  createToast(data) {
    const toast = document.createElement('div');
    toast.className = `p-4 rounded-lg shadow-lg max-w-sm transform transition-all duration-300 ${
      data.type === 'success' ? 'bg-green-500 text-white' :
      data.type === 'error' ? 'bg-red-500 text-white' :
      data.type === 'warning' ? 'bg-yellow-500 text-white' :
      'bg-blue-500 text-white'
    }`;
    
    toast.innerHTML = `
      <div class="flex items-start">
        <div class="flex-1">
          <h4 class="font-semibold">${data.title || ''}</h4>
          <p class="text-sm opacity-90">${data.message || ''}</p>
        </div>
        <button onclick="this.parentElement.parentElement.remove()" class="ml-2 text-white hover:text-gray-200">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `;
    
    return toast;
  },

  removeToast(toast) {
    if (toast.parentNode) {
      toast.classList.add('opacity-0', 'translate-x-full');
      setTimeout(() => {
        if (toast.parentNode) {
          toast.parentNode.removeChild(toast);
        }
      }, 300);
    }
  },

  // LoadingStatesHook functionality
  initializeLoadingStates() {
    console.log('LoadingStatesHook functionality initialized');
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

  createLoadingOverlay() {
    const overlay = document.createElement('div');
    overlay.id = 'loading-overlay';
    overlay.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 hidden';
    
    overlay.innerHTML = `
      <div class="bg-white rounded-lg p-6 flex items-center space-x-3">
        <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
        <span class="text-gray-700">Carregando...</span>
      </div>
    `;
    
    return overlay;
  },

  showLoading(data) {
    if (this.loadingOverlay) {
      const text = this.loadingOverlay.querySelector('span');
      if (text && data.message) {
        text.textContent = data.message;
      }
      this.loadingOverlay.classList.remove('hidden');
    }
  },

  hideLoading() {
    if (this.loadingOverlay) {
      this.loadingOverlay.classList.add('hidden');
    }
  },

  // Cleanup
  cleanup() {
    // Remove event listeners
    document.removeEventListener('keydown', this.handleKeydown);
    
    // Remove DOM elements
    if (this.toastContainer && this.toastContainer.parentNode) {
      this.toastContainer.parentNode.removeChild(this.toastContainer);
    }
    
    if (this.loadingOverlay && this.loadingOverlay.parentNode) {
      this.loadingOverlay.parentNode.removeChild(this.loadingOverlay);
    }
  }
};

export default ChatCompositeHook;
