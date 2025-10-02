const ChatHook = {
  mounted() {
    // Instant scroll on initial load
    this.scrollToBottom(false);
    this.setupEventListeners();
    this.setupTypingDetection();
  },

  updated() {
    // Only smooth scroll if user is near the bottom and not actively scrolling
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      const isNearBottom = messagesContainer.scrollTop + messagesContainer.clientHeight >= messagesContainer.scrollHeight - 100;
      const userIsScrolling = this.isUserScrolling ? this.isUserScrolling() : false;
      
      if (isNearBottom && !userIsScrolling) {
        this.scrollToBottom(true);
      }
    }
  },

  destroyed() {
    // Cleanup if needed
    if (this.typingTimeout) {
      clearTimeout(this.typingTimeout);
    }
  },

  setupEventListeners() {
    // Handle scroll to bottom events
    this.handleEvent("scroll-to-bottom", () => {
      this.scrollToBottom();
    });

    // Setup scroll detection for auto-scroll behavior
    this.setupScrollDetection();

    // Handle connection status updates
    this.handleEvent("connection-status", (data) => {
      this.updateConnectionStatus(data);
    });

    // Handle notification events
    this.handleEvent("show-notification", (data) => {
      if (window.notificationComponent) {
        window.notificationComponent.showNotification(data);
      }
    });

    this.handleEvent("show-desktop-notification", (data) => {
      if (window.notificationComponent) {
        window.notificationComponent.showDesktopNotification(data);
      }
    });

    this.handleEvent("play-notification-sound", () => {
      if (window.notificationComponent) {
        window.notificationComponent.playNotificationSound();
      }
    });

    // Handle badge count updates
    this.handleEvent("update-badge-count", () => {
      if (window.notificationComponent) {
        window.notificationComponent.updateBrowserBadge();
      }
    });

    // Handle mention suggestions
    this.handleEvent("show-user-suggestions", (data) => {
      this.showMentionSuggestions(data.users, data.query);
    });

    // Handle input changes for real-time validation and mention autocomplete
    const messageInput = this.el.querySelector('#message-input');
    if (messageInput) {
      messageInput.addEventListener('input', (e) => {
        this.validateMessage(e.target.value);
        this.handleMentionAutocomplete(e.target.value);
      });

      // Handle keyboard navigation for mentions
      messageInput.addEventListener('keydown', (e) => {
        this.handleMentionKeyboard(e);
      });
    } else {
      console.error('Message input not found!');
    }

    // Handle Enter key submission
    const form = this.el.querySelector('form');
    if (form) {
      form.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          this.submitForm();
        }
      });
    }

    // Setup drag and drop functionality
    this.setupDragAndDrop();
  },

  setupTypingDetection() {
    const messageInput = this.el.querySelector('#message-input');
    if (messageInput) {
      let typingTimer;

      messageInput.addEventListener('input', () => {
        // Clear existing timer
        if (typingTimer) {
          clearTimeout(typingTimer);
        }

        // Set new timer
        typingTimer = setTimeout(() => {
          if (this.isConnected()) {
            this.pushEvent('stop_typing', {});
          }
        }, 1000); // Stop typing after 1 second of inactivity
      });
    }
  },

  scrollToBottom(smooth = true) {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      if (smooth) {
        // Smooth scroll to bottom
        messagesContainer.scrollTo({
          top: messagesContainer.scrollHeight,
          behavior: 'smooth'
        });
      } else {
        // Instant scroll for initial load
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }
  },

  validateMessage(text) {
    const submitButton = this.el.querySelector('button[type="submit"]');
    const trimmedText = text.trim();

    if (submitButton) {
      submitButton.disabled = trimmedText === '';
    }
  },

  submitForm() {
    const messageInput = this.el.querySelector('#message-input');
    const submitButton = this.el.querySelector('button[type="submit"]');

    if (messageInput && submitButton && !submitButton.disabled) {
      const form = this.el.querySelector('form');
      if (form) {
        form.dispatchEvent(new Event('submit', { bubbles: true }));
      }
    }
  },

  updateConnectionStatus(data) {
    const statusElement = this.el.querySelector('.connection-status');
    if (statusElement) {
      statusElement.textContent = data.status;
      statusElement.className = `connection-status ${data.connected ? 'connected' : 'disconnected'}`;
    }
  },

  // Mention autocomplete methods
  handleMentionAutocomplete(text) {
    const mentionMatch = text.match(/@(\w*)$/);
    if (mentionMatch) {
      const query = mentionMatch[1];
      if (query.length >= 1) {
        this.pushEvent('search_users', { query: query });
      } else {
        this.hideMentionSuggestions();
      }
    } else {
      this.hideMentionSuggestions();
    }
  },

    showMentionSuggestions(users, query) {
    const suggestionsContainer = this.el.querySelector('#mention-suggestions');
    const suggestionsList = this.el.querySelector('#mention-suggestions-list');


    if (!suggestionsContainer || !suggestionsList) {
      return;
    }

    if (users.length === 0) {
      this.hideMentionSuggestions();
      return;
    }

    suggestionsList.innerHTML = '';

    users.forEach((user, index) => {
      const suggestionItem = document.createElement('div');
      suggestionItem.className = `px-3 py-2 hover:bg-blue-50 cursor-pointer flex items-center space-x-2 ${index === 0 ? 'bg-blue-50' : ''}`;
      suggestionItem.setAttribute('data-user', user);
      suggestionItem.setAttribute('data-index', index);

      suggestionItem.innerHTML = `
        <div class=\"w-6 h-6 bg-blue-500 rounded-full flex items-center justify-center\">
          <span class=\"text-white text-xs font-bold\">${user.charAt(0).toUpperCase()}</span>
        </div>
        <span class=\"text-sm text-gray-900\">${user}</span>
      `;

      suggestionItem.addEventListener('click', () => {
        this.selectMention(user);
      });

      suggestionsList.appendChild(suggestionItem);
    });

    suggestionsContainer.classList.remove('hidden');
    suggestionsContainer.style.display = 'block';
    suggestionsContainer.style.zIndex = 9999;
    this.currentMentionSuggestions = users;
    this.selectedMentionIndex = 0;
  },

  hideMentionSuggestions() {
    const suggestionsContainer = this.el.querySelector('#mention-suggestions');
    if (suggestionsContainer) {
      suggestionsContainer.classList.add('hidden');
      suggestionsContainer.style.display = 'none';
    }
    this.currentMentionSuggestions = [];
    this.selectedMentionIndex = 0;
    const suggestionsList = this.el.querySelector('#mention-suggestions-list');
    if (suggestionsList) {
      suggestionsList.innerHTML = '';
    }
  },

  selectMention(username) {
    const messageInput = this.el.querySelector('#message-input');
    if (!messageInput) return;

    const text = messageInput.value;
    const mentionMatch = text.match(/@(\w*)$/);

    if (mentionMatch) {
      const beforeMention = text.substring(0, mentionMatch.index);
      const afterMention = text.substring(mentionMatch.index + mentionMatch[0].length);
      const newText = beforeMention + `@${username} ` + afterMention;

      messageInput.value = newText;
      messageInput.focus();

      // Trigger change event to update LiveView
      messageInput.dispatchEvent(new Event('input', { bubbles: true }));
    }

    this.hideMentionSuggestions();
  },

  handleMentionKeyboard(event) {
    if (!this.currentMentionSuggestions) return;

    const suggestionsList = this.el.querySelector('#mention-suggestions-list');
    if (!suggestionsList) return;

    const items = suggestionsList.querySelectorAll('[data-index]');

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.selectedMentionIndex = Math.min(this.selectedMentionIndex + 1, this.currentMentionSuggestions.length - 1);
        this.updateMentionSelection(items);
        break;

      case 'ArrowUp':
        event.preventDefault();
        this.selectedMentionIndex = Math.max(this.selectedMentionIndex - 1, 0);
        this.updateMentionSelection(items);
        break;

      case 'Enter':
        if (this.currentMentionSuggestions && this.currentMentionSuggestions[this.selectedMentionIndex]) {
          event.preventDefault();
          this.selectMention(this.currentMentionSuggestions[this.selectedMentionIndex]);
        }
        break;

      case 'Escape':
        this.hideMentionSuggestions();
        break;
    }
  },

  updateMentionSelection(items) {
    items.forEach((item, index) => {
      if (index === this.selectedMentionIndex) {
        item.classList.add('bg-blue-50');
      } else {
        item.classList.remove('bg-blue-50');
      }
    });
  },

  setupScrollDetection() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      let isUserScrolling = false;
      let scrollTimeout;

      messagesContainer.addEventListener('scroll', () => {
        isUserScrolling = true;
        
        // Clear existing timeout
        if (scrollTimeout) {
          clearTimeout(scrollTimeout);
        }
        
        // Set timeout to reset user scrolling flag
        scrollTimeout = setTimeout(() => {
          isUserScrolling = false;
        }, 1000);
      });

      // Store the flag for use in updated() method
      this.isUserScrolling = () => isUserScrolling;
    }
  },

  // Drag and Drop functionality
  setupDragAndDrop() {
    const form = this.el.querySelector('form');
    const messageInput = this.el.querySelector('#message-input');
    const imageUpload = this.el.querySelector('#image-upload');


    if (!form || !messageInput || !imageUpload) {
      console.error('Required elements for drag and drop not found');
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
    const overlay = this.el.querySelector('#drag-overlay');
    
    if (highlight) {
      element.classList.add('border-blue-500', 'bg-blue-50', 'border-2', 'border-dashed');
      element.style.transition = 'all 0.2s ease-in-out';
      
      if (overlay) {
        overlay.classList.remove('opacity-0', 'pointer-events-none');
        overlay.classList.add('opacity-100');
      }
    } else {
      element.classList.remove('border-blue-500', 'bg-blue-50', 'border-2', 'border-dashed');
      
      if (overlay) {
        overlay.classList.add('opacity-0', 'pointer-events-none');
        overlay.classList.remove('opacity-100');
      }
    }
  },

  handleDroppedFiles(e, imageUpload) {
    const dt = e.dataTransfer;
    const files = dt.files;

    console.log('Files dropped:', files.length);

    if (files.length > 0) {
      // Check if files are images
      const imageFiles = Array.from(files).filter(file => {
        console.log('File type:', file.type, 'is image:', file.type.startsWith('image/'));
        return file.type.startsWith('image/');
      });

      console.log('Image files found:', imageFiles.length);

      if (imageFiles.length > 0) {
        // Use the first image file
        const file = imageFiles[0];
        console.log('Processing file:', file.name, 'size:', file.size);
        
        // Check file size (5MB limit)
        if (file.size > 5 * 1024 * 1024) {
          alert('Arquivo muito grande. Máximo permitido: 5MB');
          return;
        }

        // Create a new FileList with the dropped file
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        
        // Set the files to the input
        imageUpload.files = dataTransfer.files;
        
        // Trigger change event to notify LiveView
        const changeEvent = new Event('change', { bubbles: true });
        imageUpload.dispatchEvent(changeEvent);

        console.log('File dropped and added to upload input:', file.name);
      } else {
        alert('Por favor, solte apenas arquivos de imagem (JPG, PNG, GIF, etc.)');
      }
    }
  }
};

export default ChatHook;