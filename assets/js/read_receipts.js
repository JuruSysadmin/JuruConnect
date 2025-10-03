/**
 * Hook para marcar mensagens como lidas automaticamente
 * Observa quando mensagens aparecem na tela e as marca como lidas
 */
export const ReadReceiptsHook = {
  mounted() {
    this.initMessageObserver()
    this.setupScrollListener()
    
    // Marcar mensagens visíveis inicialmente
    this.markVisibleMessagesAsRead()
  },
  
  updated() {
    // Marcar novas mensagens que estão visíveis após update
    setTimeout(() => {
      this.markVisibleMessagesAsRead()
    }, 100)
  },
  
  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
    if (this.scrollTimer) {
      clearTimeout(this.scrollTimer)
    }
  },
  
  initMessageObserver() {
    const options = {
      root: null, // viewport
      rootMargin: '50px', // considerar 50px antes de entrar na viewport
      threshold: 0.1 // disparar quando 10% da mensagem estiver visível
    }
    
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.markMessageAsRead(entry.target)
        }
      })
    }, options)
    
    // Observar todas as mensagens existentes
    this.observeMessages()
  },
  
  setupScrollListener() {
    let lastScrollTop = 0
    let scrollTimer = null
    
    this.el.addEventListener('scroll', () => {
      clearTimeout(scrollTimer)
      scrollTimer = setTimeout(() => {
        const scrollTop = this.el.scrollTop || document.documentElement.scrollTop
        
        // Marcar mensagens visíveis quando usuário para de rolar
        this.markVisibleMessagesAsRead()
        
        lastScrollTop = scrollTop <= 0 ? 0 : scrollTop
      }, 250) // debounce de 250ms
    })
  },
  
  observeMessages() {
    const messages = this.getMessages()
    messages.forEach(message => {
      this.observer.observe(message)
    })
  },
  
  markVisibleMessagesAsRead() {
    const messages = this.getVisibleMessages()
    if (messages.length > 0) {
      const messageIds = messages.map(msg => this.getMessageId(msg))
      this.pushEventTo(this.el, 'mark_messages_as_read', { message_ids: messageIds })
    }
  },
  
  markMessageAsRead(messageElement) {
    if (this.isReadableMessage(messageElement)) {
      const messageId = this.getMessageId(messageElement)
      if (messageId) {
        this.pushEventTo(this.el, 'mark_messages_as_read', { 
          message_ids: [messageId] 
        })
      }
    }
  },
  
  getMessages() {
    // Buscar elementos de mensagem no chat - ajustar seletor conforme sua estrutura
    return this.el.querySelectorAll('[role="article"]')
  },
  
  getVisibleMessages() {
    const messages = this.getMessages()
    return Array.from(messages).filter(msg => {
      const rect = msg.getBoundingClientRect()
      const viewportHeight = window.innerHeight
      
      // Considerar visível se está entre -100px e viewport height + 100px
      return rect.top >= -100 && rect.bottom <= viewportHeight + 100
    })
  },
  
  getMessageId(messageElement) {
    // Extrair ID da mensagem do atributo ou classe CSS
    const articleElement = messageElement.closest('[role="article"]')
    if (!articleElement) return null
    
    // Tentar extrair de diferentes pontos possíveis
    const dataId = articleElement.dataset.messageId
    if (dataId) return dataId
    
    // Fallback: extrair de outras fontes
    const ariaLabel = articleElement.getAttribute('aria-label')
    if (ariaLabel) {
      const match = ariaLabel.match(/mensagem (\d+)/i)
      if (match) return match[1]
    }
    
    return null
  },
  
  isReadableMessage(messageElement) {
    // Verificar se a mensagem pode ser marcada como lida
    // Por exemplo, não marcar mensagens do próprio usuário como lidas
    
    const role = messageElement.getAttribute('role')
    if (role !== 'article') return false
    
    // Verificar se não é uma mensagem do próprio usuário
    const isCurrentUser = messageElement.classList.contains('justify-end')
    return !isCurrentUser // só marcar mensagens de outros usuários
  }
}

// Adicionar hook para modo de desenvolvimento (quando não está em LiveView)
if (typeof window !== 'undefined') {
  window.ReadReceiptsHook = ReadReceiptsHook
}
