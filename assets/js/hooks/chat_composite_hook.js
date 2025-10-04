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
    
    // Delay drag and drop setup to ensure DOM is ready
    setTimeout(() => {
      this.setupDragAndDrop();
    }, 100);
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

  // Drag and Drop functionality
  setupDragAndDrop() {
    console.log('Setting up drag and drop...');
    
    const form = this.el.querySelector('form');
    const messageInput = this.el.querySelector('#message-input');
    const imageUpload = this.el.querySelector('#image-upload');

    console.log('Elements found:', {
      form: !!form,
      messageInput: !!messageInput,
      imageUpload: !!imageUpload
    });

    if (!form || !messageInput || !imageUpload) {
      console.error('Required elements for drag and drop not found:', {
        form: form,
        messageInput: messageInput,
        imageUpload: imageUpload
      });
      return;
    }

    // Prevent default drag behaviors on the entire page
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      document.addEventListener(eventName, this.preventDefaults, false);
    });

    // Highlight drop area when item is dragged over it
    ['dragenter', 'dragover'].forEach(eventName => {
      form.addEventListener(eventName, (e) => {
        this.highlightDropArea(form, true);
      }, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
      form.addEventListener(eventName, (e) => {
        this.highlightDropArea(form, false);
      }, false);
    });

    // Handle dropped files
    form.addEventListener('drop', (e) => {
      this.handleDroppedFiles(e, imageUpload);
    }, false);
  },

  preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
  },

  highlightDropArea(element, highlight) {
    if (highlight) {
      element.classList.add('border-blue-400', 'bg-blue-50');
      element.style.transform = 'scale(1.02)';
    } else {
      element.classList.remove('border-blue-400', 'bg-blue-50');
      element.style.transform = 'scale(1)';
    }
  },

  handleDroppedFiles(e, imageUpload) {
    const dt = e.dataTransfer;
    const files = dt.files;

    console.log('Files dropped:', files.length);

    if (files.length > 0) {
      // Filter only image files
      const imageFiles = Array.from(files).filter(file => {
        return file.type.startsWith('image/');
      });

      if (imageFiles.length > 0) {
        // Validate image files
        const validFiles = imageFiles.filter(file => {
          if (file.size > 5 * 1024 * 1024) {
            this.showError('Arquivo muito grande. Máximo permitido: 5MB');
            return false;
          }
          return true;
        });

        if (validFiles.length === 0) {
          return;
        }

        // Limit to 3 files maximum
        const filesToUpload = validFiles.slice(0, 3);
        
        if (validFiles.length > 3) {
          this.showError('Máximo de 3 imagens permitidas. Apenas as primeiras 3 serão enviadas.');
        }

        // Transfer files to LiveView input
        this.transferFilesToLiveView(filesToUpload, imageUpload);
        
      } else {
        this.showError('Por favor, solte apenas arquivos de imagem (JPG, PNG, GIF, etc.)');
      }
    }
  },

  transferFilesToLiveView(files, imageUpload) {
    // Create a new FileList with the dropped files
    const dataTransfer = new DataTransfer();
    files.forEach(file => {
      dataTransfer.items.add(file);
    });
    
    // Set the files to the input
    imageUpload.files = dataTransfer.files;
    
    // Trigger change event to notify LiveView
    const changeEvent = new Event('change', { bubbles: true });
    imageUpload.dispatchEvent(changeEvent);

    console.log('Files transferred to LiveView:', files.length);
  },

  showError(message) {
    // Use the existing toast notification system
    this.pushEvent("show-toast", {
      type: "error",
      title: "Erro no upload",
      message: message,
      duration: 5000
    });
  },

  // Cleanup
  cleanup() {
    // Remove event listeners
    document.removeEventListener('keydown', this.handleKeydown);
    
    // Remove drag and drop listeners
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      document.removeEventListener(eventName, this.preventDefaults, false);
    });
    
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
