// Keyboard Shortcuts Hook for Chat
export const KeyboardShortcutsHook = {
  mounted() {
    this.handleKeydown = this.handleKeydown.bind(this);
    document.addEventListener('keydown', this.handleKeydown);
    
    // Show shortcuts help on first visit
    this.showShortcutsHelp();
  },

  destroyed() {
    document.removeEventListener('keydown', this.handleKeydown);
  },

  handleKeydown(event) {
    // Don't interfere with form inputs, textareas, or contenteditable elements
    if (this.isInputElement(event.target)) {
      return;
    }

    // Ctrl+K or Cmd+K - Open search
    if ((event.ctrlKey || event.metaKey) && event.key === 'k') {
      event.preventDefault();
      this.pushEvent('toggle_search');
      // Focus search input after a short delay
      setTimeout(() => {
        const searchInput = document.querySelector('input[placeholder*="Buscar"]');
        if (searchInput) {
          searchInput.focus();
        }
      }, 100);
    }

    // ESC - Close modals and sidebars
    if (event.key === 'Escape') {
      event.preventDefault();
      this.pushEvent('close_all_modals');
    }

    // Ctrl+/ or Cmd+/ - Show shortcuts help
    if ((event.ctrlKey || event.metaKey) && event.key === '/') {
      event.preventDefault();
      this.pushEvent('show_shortcuts_help');
    }

    // Ctrl+Enter or Cmd+Enter - Send message (when in message input)
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      const messageInput = document.querySelector('#message-input');
      if (messageInput && messageInput === document.activeElement) {
        event.preventDefault();
        this.pushEvent('send_message', { message: messageInput.value });
      }
    }

    // Arrow keys for navigation
    if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
      this.handleArrowNavigation(event);
    }

    // Number keys for quick actions
    if (event.key >= '1' && event.key <= '9' && !event.ctrlKey && !event.metaKey) {
      this.handleNumberShortcuts(event);
    }
  },

  isInputElement(element) {
    const inputTypes = ['input', 'textarea', 'select'];
    const isContentEditable = element.contentEditable === 'true';
    const isInput = inputTypes.includes(element.tagName.toLowerCase());
    const isInInput = element.closest('input, textarea, select, [contenteditable="true"]');
    
    return isInput || isContentEditable || isInInput;
  },

  handleArrowNavigation(event) {
    // Navigate through messages with arrow keys
    const messages = document.querySelectorAll('[role="article"]');
    if (messages.length === 0) return;

    const currentFocused = document.activeElement;
    const currentIndex = Array.from(messages).indexOf(currentFocused);
    
    let nextIndex;
    if (event.key === 'ArrowUp') {
      nextIndex = currentIndex > 0 ? currentIndex - 1 : messages.length - 1;
    } else {
      nextIndex = currentIndex < messages.length - 1 ? currentIndex + 1 : 0;
    }

    if (nextIndex !== -1) {
      messages[nextIndex].focus();
      messages[nextIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  },

  handleNumberShortcuts(event) {
    const number = parseInt(event.key);
    
    // Quick actions based on number keys
    switch (number) {
      case 1:
        // Focus message input
        const messageInput = document.querySelector('#message-input');
        if (messageInput) {
          messageInput.focus();
        }
        break;
      case 2:
        // Toggle sidebar
        this.pushEvent('toggle_sidebar');
        break;
      case 3:
        // Show tag modal
        this.pushEvent('show_tag_modal');
        break;
      case 4:
        // Exit chat
        this.pushEvent('exit_chat');
        break;
    }
  },

  showShortcutsHelp() {
    // Check if user has seen shortcuts help before
    const hasSeenHelp = localStorage.getItem('chat_shortcuts_seen');
    if (!hasSeenHelp) {
      setTimeout(() => {
        this.pushEvent('show_shortcuts_tour');
        localStorage.setItem('chat_shortcuts_seen', 'true');
      }, 2000);
    }
  }
};
