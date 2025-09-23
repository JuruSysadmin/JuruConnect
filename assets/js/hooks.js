/**
 * @fileoverview Hooks personalizados para animações e celebrações
 * @author JuruConnect Team
 * @version 1.0.0
 */


/**
 * Hook para animações de crescimento nas vendas
 * Detecta mudanças nos valores e aplica animações visuais
 * @namespace SalesGrowthAnimation
 */
let SalesGrowthAnimation = {
  /**
   * Inicializa o hook quando o elemento é montado no DOM
   * Armazena valores anteriores para comparação
   * @memberof SalesGrowthAnimation
   */
  mounted() {
    // Armazena valores iniciais para comparação
    this.previousValues = new Map()
    this.initializeValues()
    
    // Listener para atualizações de dados
    this.handleEvent("sales-updated", (data) => {
      this.checkForGrowth(data)
    })
  },

  /**
   * Inicializa os valores atuais para comparação futura
   * @memberof SalesGrowthAnimation
   */
  initializeValues() {
    const rows = this.el.querySelectorAll('tbody tr')
    rows.forEach((row, index) => {
      const salesCell = row.querySelector('td:nth-child(5)') // Coluna de vendas
      if (salesCell) {
        const value = this.extractNumericValue(salesCell.textContent)
        this.previousValues.set(index, value)
      }
    })
  },

  /**
   * Verifica se houve crescimento e aplica animação
   * @memberof SalesGrowthAnimation
   * @param {Object} data - Dados atualizados das lojas
   */
  checkForGrowth(data) {
    if (!data.lojas_data) return

    data.lojas_data.forEach((loja, index) => {
      const previousValue = this.previousValues.get(index) || 0
      const currentValue = loja.venda_dia || 0

      if (currentValue > previousValue) {
        this.animateGrowth(index, currentValue - previousValue)
      }

      // Atualiza valor anterior
      this.previousValues.set(index, currentValue)
    })
  },

  /**
   * Aplica animação de crescimento em uma linha específica
   * @memberof SalesGrowthAnimation
   * @param {number} rowIndex - Índice da linha
   * @param {number} growthAmount - Quantidade de crescimento
   */
  animateGrowth(rowIndex, growthAmount) {
    const rows = this.el.querySelectorAll('tbody tr')
    const row = rows[rowIndex]
    
    if (!row) return

    const salesCell = row.querySelector('td:nth-child(5)')
    if (!salesCell) return

    // Cria elemento de animação
    const animationElement = document.createElement('div')
    animationElement.className = 'sales-growth-animation'
    animationElement.innerHTML = `
      <div class="growth-arrow">↗</div>
      <div class="growth-amount">+${this.formatMoney(growthAmount)}</div>
    `
    
    // Posiciona o elemento
    animationElement.style.position = 'absolute'
    animationElement.style.right = '10px'
    animationElement.style.top = '50%'
    animationElement.style.transform = 'translateY(-50%)'
    animationElement.style.zIndex = '10'
    animationElement.style.pointerEvents = 'none'
    
    // Adiciona ao DOM
    salesCell.style.position = 'relative'
    salesCell.appendChild(animationElement)
    
    // Remove após animação
    setTimeout(() => {
      if (animationElement.parentNode) {
        animationElement.parentNode.removeChild(animationElement)
      }
    }, 2000)
  },

  /**
   * Extrai valor numérico de uma string formatada
   * @memberof SalesGrowthAnimation
   * @param {string} text - Texto com valor formatado
   * @returns {number} Valor numérico
   */
  extractNumericValue(text) {
    // Remove R$, espaços e substitui vírgula por ponto
    const cleanText = text.replace(/[R$\s]/g, '').replace(',', '.')
    return parseFloat(cleanText) || 0
  },

  /**
   * Formata valor monetário para exibição
   * @memberof SalesGrowthAnimation
   * @param {number} value - Valor numérico
   * @returns {string} Valor formatado
   */
  formatMoney(value) {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL'
    }).format(value)
  }
}


/**
 * Hook para celebração de metas
 * @namespace GoalCelebration
 */
let GoalCelebration = {
  mounted() {
    // Listener para eventos de celebração
    this.handleEvent("goal-achieved-multiple", (data) => {
      this.showCelebration(data)
    })
    
    this.handleEvent("goal-achieved-real", (data) => {
      this.showCelebration(data)
    })
  },

  showCelebration(data) {
    // Criar elemento de celebração
    const celebration = document.createElement('div')
    celebration.className = 'goal-celebration'
    celebration.innerHTML = `
      <div class="celebration-content">
        <div class="celebration-icon">🎉</div>
        <div class="celebration-text">
          <div class="celebration-title">Meta Atingida!</div>
          <div class="celebration-store">${data.store_name}</div>
          <div class="celebration-amount">${data.achieved}</div>
        </div>
      </div>
    `
    
    // Posicionar no centro da tela
    celebration.style.position = 'fixed'
    celebration.style.top = '50%'
    celebration.style.left = '50%'
    celebration.style.transform = 'translate(-50%, -50%)'
    celebration.style.zIndex = '9999'
    celebration.style.pointerEvents = 'none'
    
    // Adicionar ao DOM
    document.body.appendChild(celebration)
    
    // Remover após 3 segundos
    setTimeout(() => {
      if (celebration.parentNode) {
        celebration.parentNode.removeChild(celebration)
      }
    }, 3000)
  }
}

export default { SalesGrowthAnimation, GoalCelebration }