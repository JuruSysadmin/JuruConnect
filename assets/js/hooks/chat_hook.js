/**
 * @fileoverview Hook do Phoenix LiveView para funcionalidades de chat em tempo real
 * @author JuruConnect Team
 * @version 1.0.0
 */

/**
 * Hook para gerenciar funcionalidades do chat incluindo auto-scroll,
 * redimensionamento automático do input e envio de mensagens
 * @namespace ChatHook
 */
const ChatHook = {
  /**
   * Inicializa o hook quando o elemento é montado no DOM
   * Configura listeners para scroll automático, redimensionamento de input e envio com Enter
   * @memberof ChatHook
   */
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

  /**
   * Faz scroll automático para a última mensagem do chat
   * Usado para manter o chat sempre mostrando as mensagens mais recentes
   * @memberof ChatHook
   */
  scrollToBottom() {
    const messagesContainer = this.el.querySelector('#messages');
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
  },

  /**
   * Callback executado quando o componente é atualizado pelo LiveView
   * Garante que o scroll seja mantido na posição correta após atualizações
   * @memberof ChatHook
   */
  updated() {
    // Scroll para baixo quando o componente é atualizado
    this.scrollToBottom();
  }
};

export default ChatHook; 