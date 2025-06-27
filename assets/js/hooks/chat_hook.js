const ChatHook = {
  mounted() {
    this.scrollToBottom();
    
    // Auto-scroll quando novas mensagens chegam
    this.handleEvent("scroll-to-bottom", () => {
      this.scrollToBottom();
    });

    // Auto-resize do input
    const input = this.el.querySelector('input[name="message"]');
    if (input) {
      input.addEventListener('input', () => {
        input.style.height = 'auto';
        input.style.height = input.scrollHeight + 'px';
      });
    }

    // Enviar mensagem com Enter
    const form = this.el.querySelector('form');
    if (form) {
      form.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          form.dispatchEvent(new Event('submit', { bubbles: true }));
        }
      });
    }
  },

  scrollToBottom() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
  },

  updated() {
    // Scroll para baixo quando o componente é atualizado
    this.scrollToBottom();
  }
};

export default ChatHook; 