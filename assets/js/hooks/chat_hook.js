const ChatHook = {
  mounted() {
    console.log('ChatHook mounted - autocomplete system initialized');
    console.log('Hook element:', this.el);
    this.scrollToBottom();
    this.setupEventListeners();
    this.setupTypingDetection();
  },

  updated() {
    this.scrollToBottom();
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

    // Handle mention suggestions
    this.handleEvent("show-user-suggestions", (data) => {
      console.log('show-user-suggestions event received:', data);
      this.showMentionSuggestions(data.users, data.query);
    });

    // Handle input changes for real-time validation and mention autocomplete
    const messageInput = this.el.querySelector('#message-input');
    console.log('Message input found:', messageInput);
    if (messageInput) {
      console.log('Setting up input event listeners for autocomplete');
      messageInput.addEventListener('input', (e) => {
        console.log('Input event triggered:', e.target.value);
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
          this.pushEvent('stop_typing', {});
        }, 1000); // Stop typing after 1 second of inactivity
      });
    }
  },

  scrollToBottom() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
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
    console.log('handleMentionAutocomplete called with:', text);
    const mentionMatch = text.match(/@(\w*)$/);
    if (mentionMatch) {
      const query = mentionMatch[1];
      console.log('Mention match found, query:', query);
      if (query.length >= 1) {
        console.log('Pushing search_users event with query:', query);
        this.pushEvent('search_users', { query: query });
      } else {
        console.log('Query too short, hiding suggestions');
        this.hideMentionSuggestions();
      }
    } else {
      console.log('No mention match, hiding suggestions');
      this.hideMentionSuggestions();
    }
  },

    showMentionSuggestions(users, query) {
    console.log('showMentionSuggestions called with:', users, query);
    const suggestionsContainer = this.el.querySelector('#mention-suggestions');
    const suggestionsList = this.el.querySelector('#mention-suggestions-list');

    console.log('Found elements:', { suggestionsContainer, suggestionsList });

    if (!suggestionsContainer || !suggestionsList) {
      console.log('Missing elements, returning');
      return;
    }

    if (users.length === 0) {
      console.log('No users found, hiding suggestions');
      this.hideMentionSuggestions();
      return;
    }

    console.log('Creating suggestions for users:', users);
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

    console.log('Showing suggestions container');
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
  }
};

export default ChatHook;