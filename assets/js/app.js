/**
 * @fileoverview Arquivo principal do Phoenix LiveView com hooks para gráficos e interações
 * @author JuruConnect Team
 * @version 1.0.0
 */

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Chart from 'chart.js/auto';
import ChatHook from './hooks/chat_hook.js'

/**
 * Coleção de hooks do Phoenix LiveView
 * @type {Object}
 */
let Hooks = {}

Hooks.ChatHook = ChatHook

/**
 * Hook para gráficos de rosca básicos usando Chart.js
 * @namespace Hooks.Chart
 */
Hooks.Chart = {
  /**
   * Inicializa o gráfico quando o elemento é montado no DOM
   * @memberof Hooks.Chart
   */
  mounted() {
    const ctx = this.el.getContext('2d');
    const data = JSON.parse(this.el.dataset.chartData);
    
    new Chart(ctx, {
      type: 'doughnut',
      data: data,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom'
          }
        }
      }
    });
  }
}

/**
 * Hook para gráficos de gauge (medidor) com animações suaves
 * @namespace Hooks.GaugeChart
 */
Hooks.GaugeChart = {
  /**
   * Inicializa o gauge chart e configura listeners de eventos
   * @memberof Hooks.GaugeChart
   */
  mounted() {
    this.initChart();
    this.handleEvent("update-gauge", (data) => {
      this.updateChart(data.value);
    });
  },
  
  /**
   * Cria o gráfico de gauge inicial
   * @memberof Hooks.GaugeChart
   */
  initChart() {
    const ctx = this.el.getContext('2d');
    const value = parseFloat(this.el.dataset.value) || 0;
    
    this.chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        datasets: [{
          data: [value, 100 - value],
          backgroundColor: [
            this.getColor(value),
            '#F3F4F6'
          ],
          borderWidth: 0,
          borderRadius: 8
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '75%',
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            enabled: false
          }
        },
        animation: {
          animateRotate: true,
          duration: 1000
        }
      }
    });
  },
  
  /**
   * Atualiza o valor do gauge com animação
   * @memberof Hooks.GaugeChart
   * @param {number} value - Novo valor para o gauge (0-100)
   */
  updateChart(value) {
    if (this.chart) {
      this.chart.data.datasets[0].data = [value, 100 - value];
      this.chart.data.datasets[0].backgroundColor[0] = this.getColor(value);
      this.chart.update('active');
    }
  },
  
  /**
   * Retorna a cor baseada no valor do gauge
   * @memberof Hooks.GaugeChart
   * @param {number} value - Valor de 0 a 100
   * @returns {string} Código hexadecimal da cor
   */
  getColor(value) {
    if (value >= 100) return '#059669'; // Green-600
    if (value >= 80) return '#10B981';  // Green-500
    if (value >= 60) return '#F59E0B';  // Yellow-500
    if (value >= 40) return '#F97316';  // Orange-500
    return '#EF4444'; // Red-500
  },
  
  /**
   * Callback executado quando o elemento é atualizado
   * @memberof Hooks.GaugeChart
   */
  updated() {
    const value = parseFloat(this.el.dataset.value) || 0;
    this.updateChart(value);
  }
}

/**
 * Hook especializado para gauge mensal com animações mais suaves
 * @namespace Hooks.GaugeChartMonthly
 */
Hooks.GaugeChartMonthly = {
  /**
   * Inicializa o gauge mensal e configura listeners
   * @memberof Hooks.GaugeChartMonthly
   */
  mounted() {
    this.initChart();
    this.handleEvent("update-gauge-monthly", (data) => {
      this.updateChart(data.value);
    });
  },
  
  /**
   * Cria o gráfico de gauge mensal com configurações específicas
   * @memberof Hooks.GaugeChartMonthly
   */
  initChart() {
    const ctx = this.el.getContext('2d');
    const value = parseFloat(this.el.dataset.value) || 0;
    
    this.chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        datasets: [{
          data: [value, 100 - value],
          backgroundColor: [
            this.getColor(value),
            '#F3F4F6'
          ],
          borderWidth: 0,
          borderRadius: 8
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '75%',
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            enabled: false
          }
        },
        animation: {
          animateRotate: true,
          duration: 1500, // Animação um pouco mais lenta para efeito suave
          easing: 'easeOutQuart'
        }
      }
    });
  },
  
  /**
   * Atualiza o gauge mensal com animação inteligente
   * @memberof Hooks.GaugeChartMonthly
   * @param {number} value - Novo valor para o gauge (0-100)
   */
  updateChart(value) {
    if (this.chart) {
      // Preserva o valor atual para animação suave
      const currentValue = this.chart.data.datasets[0].data[0];
      const targetValue = Math.min(value, 100);
      
      // Se for uma diferença pequena, anima suavemente
      if (Math.abs(targetValue - currentValue) < 10) {
        this.animateToValue(currentValue, targetValue);
      } else {
        // Para mudanças grandes, atualiza diretamente
        this.chart.data.datasets[0].data = [targetValue, 100 - targetValue];
        this.chart.data.datasets[0].backgroundColor[0] = this.getColor(targetValue);
        this.chart.update('active');
      }
    }
  },
  
  /**
   * Anima suavemente entre dois valores
   * @memberof Hooks.GaugeChartMonthly
   * @param {number} startValue - Valor inicial
   * @param {number} endValue - Valor final
   */
  animateToValue(startValue, endValue) {
    const duration = 1000;
    const startTime = performance.now();
    
    const animate = (currentTime) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);
      
      // Easing function para suavidade
      const easeProgress = 1 - Math.pow(1 - progress, 3);
      const currentValue = startValue + (endValue - startValue) * easeProgress;
      
      this.chart.data.datasets[0].data = [currentValue, 100 - currentValue];
      this.chart.data.datasets[0].backgroundColor[0] = this.getColor(currentValue);
      this.chart.update('none'); // Update sem animação para controle manual
      
      if (progress < 1) {
        requestAnimationFrame(animate);
      }
    };
    
    requestAnimationFrame(animate);
  },
  
  /**
   * Retorna a cor baseada no valor do gauge
   * @memberof Hooks.GaugeChartMonthly
   * @param {number} value - Valor de 0 a 100
   * @returns {string} Código hexadecimal da cor
   */
  getColor(value) {
    if (value >= 100) return '#059669'; // Green-600
    if (value >= 80) return '#10B981';  // Green-500
    if (value >= 60) return '#F59E0B';  // Yellow-500
    if (value >= 40) return '#F97316';  // Orange-500
    return '#EF4444'; // Red-500
  },
  
  /**
   * Callback executado quando o elemento é atualizado
   * @memberof Hooks.GaugeChartMonthly
   */
  updated() {
    const value = parseFloat(this.el.dataset.value) || 0;
    this.updateChart(value);
  }
}

/**
 * Hook para celebração de metas atingidas com efeitos visuais e sonoros
 * @namespace Hooks.GoalCelebration
 */
Hooks.GoalCelebration = {
  /**
   * Configura o listener para eventos de meta atingida
   * @memberof Hooks.GoalCelebration
   */
  mounted() {
    this.handleEvent("goal-achieved", (data) => {
      this.celebrate(data);
    });
  },
  
  /**
   * Executa a celebração completa com som, toast e confetti
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da meta atingida
   * @param {string} data.store_name - Nome da loja
   * @param {string} data.achieved - Valor atingido formatado
   */
  celebrate(data) {
    // Efeito sonoro (opcional - só funciona com interação do usuário)
    this.playSound();
    
    // Mostra toast notification
    this.showToast(data.store_name, data.achieved);
    
    // Efeito de confetti
    this.createConfetti();
  },
  
  /**
   * Reproduz um som de sucesso usando Web Audio API
   * @memberof Hooks.GoalCelebration
   */
  playSound() {
    try {
      // Cria um som de sucesso usando Web Audio API
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();
      
      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);
      
      oscillator.frequency.setValueAtTime(800, audioContext.currentTime);
      oscillator.frequency.exponentialRampToValueAtTime(1200, audioContext.currentTime + 0.1);
      
      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5);
      
      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.5);
    } catch (e) {
      // Audio not available
    }
  },
  
  /**
   * Exibe uma notificação toast no canto da tela
   * @memberof Hooks.GoalCelebration
   * @param {string} storeName - Nome da loja
   * @param {string} achieved - Valor atingido formatado
   */
  showToast(storeName, achieved) {
    // Cria uma notificação temporária no canto da tela
    const toast = document.createElement('div');
    toast.className = 'fixed top-4 right-4 bg-green-500 text-white p-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300';
    toast.innerHTML = `
      <div class="flex items-center space-x-2">
        <span class="text-2xl"></span>
        <div>
          <div class="font-bold">Meta Atingida!</div>
          <div class="text-sm">${storeName}</div>
          <div class="text-xs">${achieved}</div>
        </div>
      </div>
    `;
    
    document.body.appendChild(toast);
    
    // Anima para dentro
    setTimeout(() => {
      toast.classList.remove('translate-x-full');
    }, 100);
    
    // Remove após 4 segundos
    setTimeout(() => {
      toast.classList.add('translate-x-full');
      setTimeout(() => {
        document.body.removeChild(toast);
      }, 300);
    }, 4000);
  },
  
  /**
   * Cria efeito de confetti com múltiplas partículas
   * @memberof Hooks.GoalCelebration
   */
  createConfetti() {
    // Cria partículas de confetti
    for (let i = 0; i < 50; i++) {
      setTimeout(() => {
        this.createConfettiPiece();
      }, i * 50);
    }
  },
  
  /**
   * Cria uma única partícula de confetti animada
   * @memberof Hooks.GoalCelebration
   */
  createConfettiPiece() {
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD'];
    const confetti = document.createElement('div');
    
    confetti.style.position = 'fixed';
    confetti.style.top = '-10px';
    confetti.style.left = Math.random() * window.innerWidth + 'px';
    confetti.style.width = '10px';
    confetti.style.height = '10px';
    confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    confetti.style.borderRadius = '50%';
    confetti.style.pointerEvents = 'none';
    confetti.style.zIndex = '9999';
    confetti.style.animation = `confettifall 3s linear forwards`;
    
    document.body.appendChild(confetti);
    
    setTimeout(() => {
      if (confetti.parentNode) {
        confetti.parentNode.removeChild(confetti);
      }
    }, 3000);
  }
}

/**
 * Token CSRF obtido do meta tag
 * @type {string}
 */
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

/**
 * Instância principal do LiveSocket
 * @type {LiveSocket}
 */
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(100))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

