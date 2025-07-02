/**
 * @fileoverview Hooks personalizados para gráficos gauge usando Canvas HTML5
 * @author JuruConnect Team
 * @version 1.0.0
 */

/**
 * Hook para gráfico de gauge (medidor) usando Canvas HTML5
 * Renderiza um gauge semicircular com cores dinâmicas baseadas no valor
 * @namespace GaugeChart
 */
let GaugeChart = {
  /**
   * Inicializa o hook quando o elemento é montado no DOM
   * Configura o gráfico inicial e listeners para atualizações
   * @memberof GaugeChart
   */
  mounted() {
    this.initChart()
    this.handleEvent("update-gauge", (data) => {
      this.updateChart(data.value)
    })
  },

  /**
   * Inicializa o gráfico de gauge no canvas
   * Define dimensões e desenha o estado inicial
   * @memberof GaugeChart
   */
  initChart() {
    const canvas = this.el
    const ctx = canvas.getContext('2d')
    const value = parseFloat(canvas.dataset.value) || 0
    
    // Set canvas size
    canvas.width = 300
    canvas.height = 200
    
    this.drawGauge(ctx, value)
  },

  /**
   * Atualiza o gráfico com um novo valor
   * Limpa o canvas e redesenha com o novo valor
   * @memberof GaugeChart
   * @param {number} value - Novo valor para o gauge (0-100)
   */
  updateChart(value) {
    const canvas = this.el
    const ctx = canvas.getContext('2d')
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    this.drawGauge(ctx, value)
  },

  /**
   * Desenha o gauge no contexto do canvas
   * Renderiza arco de fundo, arco de progresso, ponto central e texto do valor
   * @memberof GaugeChart
   * @param {CanvasRenderingContext2D} ctx - Contexto 2D do canvas
   * @param {number} value - Valor a ser exibido (0-100)
   */
  drawGauge(ctx, value) {
    const centerX = 150
    const centerY = 120
    const radius = 80
    const startAngle = Math.PI
    const endAngle = 2 * Math.PI
    
    // Normalize value to 0-100
    const normalizedValue = Math.min(Math.max(value, 0), 100)
    const progressAngle = startAngle + (normalizedValue / 100) * (endAngle - startAngle)
    
    // Background arc
    ctx.beginPath()
    ctx.arc(centerX, centerY, radius, startAngle, endAngle)
    ctx.lineWidth = 20
    ctx.strokeStyle = '#e5e7eb'
    ctx.stroke()
    
    // Progress arc
    ctx.beginPath()
    ctx.arc(centerX, centerY, radius, startAngle, progressAngle)
    ctx.lineWidth = 20
    
    // Color based on progress
    if (normalizedValue < 50) {
      ctx.strokeStyle = '#ef4444' // Red
    } else if (normalizedValue < 80) {
      ctx.strokeStyle = '#f59e0b' // Yellow
    } else {
      ctx.strokeStyle = '#10b981' // Green
    }
    ctx.stroke()
    
    // Center dot
    ctx.beginPath()
    ctx.arc(centerX, centerY, 8, 0, 2 * Math.PI)
    ctx.fillStyle = '#374151'
    ctx.fill()
    
    // Value text
    ctx.font = 'bold 24px Arial'
    ctx.fillStyle = '#374151'
    ctx.textAlign = 'center'
    ctx.fillText(`${normalizedValue.toFixed(1)}%`, centerX, centerY + 50)
  }
}

export default { GaugeChart } 