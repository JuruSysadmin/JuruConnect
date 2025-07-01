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

/**
 * Hook para auto-dismiss das mensagens de flash
 * @namespace Hooks.AutoDismissFlash
 */
Hooks.AutoDismissFlash = {
  /**
   * Inicializa o auto-dismiss quando a mensagem é montada
   * @memberof Hooks.AutoDismissFlash
   */
  mounted() {
    const kind = this.el.dataset.kind;
    
    // Auto-dismiss apenas para mensagens de sucesso (info), não para erro
    if (kind === 'info') {
      this.timeout = setTimeout(() => {
        // Simula o clique para fechar a mensagem
        this.el.click();
      }, 4000); // 4 segundos
    }
  },
  
  /**
   * Limpa o timeout quando o elemento é destruído
   * @memberof Hooks.AutoDismissFlash
   */
  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout);
    }
  }
};

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

    this.handleEvent("goal-achieved-multiple", (data) => {
      this.celebrateMultiple(data);
    });

    // Novo handler para celebrações reais baseadas em dados da API
    this.handleEvent("goal-achieved-real", (data) => {
      this.celebrateReal(data);
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
  },

  /**
   * Celebração múltipla com efeitos mais intensos
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da celebração múltipla
   */
  celebrateMultiple(data) {
    // Som mais elaborado
    this.playAdvancedSound();
    
    // Toast com informações extra
    this.showEnhancedToast(data.store_name, data.achieved, data.celebration_id);
    
    // Confetti mais intenso
    this.createIntenseConfetti();
  },

  /**
   * Celebração real baseada em dados da API com níveis diferentes
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da celebração real
   */
  celebrateReal(data) {
    // Som baseado no nível
    this.playLevelSound(data.level);
    
    // Toast personalizado baseado no tipo
    this.showRealToast(data);
    
    // Confetti baseado no nível
    this.createLevelConfetti(data.level);
    
    // Efeito especial para níveis épicos
    if (data.level === 'legendary' || data.level === 'epic') {
      this.createFireworks();
    }
  },

  /**
   * Som mais elaborado para celebrações múltiplas
   * @memberof Hooks.GoalCelebration
   */
  playAdvancedSound() {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      
      // Sequência de notas
      const notes = [523.25, 659.25, 783.99]; // C5, E5, G5
      
      notes.forEach((freq, index) => {
        setTimeout(() => {
          const oscillator = audioContext.createOscillator();
          const gainNode = audioContext.createGain();
          
          oscillator.connect(gainNode);
          gainNode.connect(audioContext.destination);
          
          oscillator.frequency.setValueAtTime(freq, audioContext.currentTime);
          gainNode.gain.setValueAtTime(0.2, audioContext.currentTime);
          gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3);
          
          oscillator.start(audioContext.currentTime);
          oscillator.stop(audioContext.currentTime + 0.3);
        }, index * 200);
      });
    } catch (e) {
      // Som não disponível
    }
  },

  /**
   * Som baseado no nível da celebração
   * @memberof Hooks.GoalCelebration
   * @param {string} level - Nível da celebração
   */
  playLevelSound(level) {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      let frequency, duration, gain;
      
      switch (level) {
        case 'legendary':
          frequency = [440, 554.37, 659.25, 880]; // A4-C#5-E5-A5
          duration = 0.6;
          gain = 0.4;
          break;
        case 'epic':
          frequency = [523.25, 659.25, 783.99]; // C5-E5-G5
          duration = 0.5;
          gain = 0.3;
          break;
        case 'major':
          frequency = [440, 554.37]; // A4-C#5
          duration = 0.4;
          gain = 0.25;
          break;
        case 'standard':
          frequency = [523.25]; // C5
          duration = 0.3;
          gain = 0.2;
          break;
        default:
          frequency = [440]; // A4
          duration = 0.2;
          gain = 0.15;
      }
      
      frequency.forEach((freq, index) => {
        setTimeout(() => {
          const oscillator = audioContext.createOscillator();
          const gainNode = audioContext.createGain();
          
          oscillator.connect(gainNode);
          gainNode.connect(audioContext.destination);
          
          oscillator.frequency.setValueAtTime(freq, audioContext.currentTime);
          gainNode.gain.setValueAtTime(gain, audioContext.currentTime);
          gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + duration);
          
          oscillator.start(audioContext.currentTime);
          oscillator.stop(audioContext.currentTime + duration);
        }, index * 150);
      });
    } catch (e) {
      // Som não disponível
    }
  },

  /**
   * Toast aprimorado para celebrações múltiplas
   * @memberof Hooks.GoalCelebration
   */
  showEnhancedToast(storeName, achieved, celebrationId) {
    const toast = document.createElement('div');
    toast.className = 'fixed top-4 right-4 bg-gradient-to-r from-green-500 to-emerald-600 text-white p-4 rounded-lg shadow-2xl z-50 transform translate-x-full transition-all duration-500 border-2 border-yellow-300';
    toast.innerHTML = `
      <div class="flex items-center space-x-3">
        <div>
          <div class="font-bold text-lg">META ATINGIDA!</div>
          <div class="text-sm font-medium">${storeName}</div>
          <div class="text-lg font-mono font-bold text-yellow-200">${achieved}</div>
          <div class="text-xs opacity-75">#${celebrationId}</div>
        </div>
      </div>
    `;
    
    document.body.appendChild(toast);
    
    setTimeout(() =>toast.classList.remove('translate-x-full'), 100);
    setTimeout(() => {
      toast.classList.add('translate-x-full');
      setTimeout(() => document.body.removeChild(toast), 500);
    }, 6000);
  },

  /**
   * Toast personalizado para celebrações reais
   * @memberof Hooks.GoalCelebration
   */
  showRealToast(data) {
    const levelColors = {
      legendary: 'from-purple-600 to-pink-600 border-yellow-400',
      epic: 'from-orange-500 to-red-600 border-orange-300',
      major: 'from-blue-500 to-indigo-600 border-blue-300',
      standard: 'from-green-500 to-emerald-600 border-green-300',
      minor: 'from-gray-500 to-gray-600 border-gray-300'
    };

    const colorClass = levelColors[data.level] || levelColors.standard;

    const toast = document.createElement('div');
    toast.className = `fixed top-4 right-4 bg-gradient-to-r ${colorClass} text-white p-4 rounded-xl shadow-2xl z-50 transform translate-x-full transition-all duration-500 border-2 max-w-sm`;
    
    let storeInfo = data.store_name !== 'Sistema' ? `<div class="text-sm font-medium">${data.store_name}</div>` : '';
    
    toast.innerHTML = `
      <div class="flex items-start space-x-3">
        <div class="flex-1">
          <div class="font-bold text-base">${data.message}</div>
          ${storeInfo}
          <div class="text-lg font-mono font-bold text-yellow-100">${data.achieved}</div>
          <div class="text-xs opacity-75 mt-1">
            ${data.type} • ${data.percentage}% • Nível ${data.level}
          </div>
        </div>
      </div>
    `;
    
    document.body.appendChild(toast);
    
    setTimeout(() => toast.classList.remove('translate-x-full'), 100);
    
    // Duração baseada no nível
    const duration = this.getToastDuration(data.level);
    setTimeout(() => {
      toast.classList.add('translate-x-full');
      setTimeout(() => document.body.removeChild(toast), 500);
    }, duration);
  },

  /**
   * Confetti mais intenso para celebrações múltiplas
   * @memberof Hooks.GoalCelebration
   */
  createIntenseConfetti() {
    // Mais partículas e mais coloridas
    for (let i = 0; i < 100; i++) {
      setTimeout(() => {
        this.createEnhancedConfettiPiece();
      }, i * 30);
    }
  },

  /**
   * Confetti baseado no nível da celebração
   * @memberof Hooks.GoalCelebration
   */
  createLevelConfetti(level) {
    const particleCount = {
      legendary: 150,
      epic: 100,
      major: 75,
      standard: 50,
      minor: 25
    };

    const count = particleCount[level] || 50;
    
    for (let i = 0; i < count; i++) {
      setTimeout(() => {
        this.createLevelConfettiPiece(level);
      }, i * 40);
    }
  },

  /**
   * Partícula de confetti aprimorada
   * @memberof Hooks.GoalCelebration
   */
  createEnhancedConfettiPiece() {
    const colors = ['#FFD700', '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD', '#FF69B4'];
    const shapes = ['circle', 'square', 'triangle'];
    
    const confetti = document.createElement('div');
    const shape = shapes[Math.floor(Math.random() * shapes.length)];
    const size = Math.random() * 8 + 4; // 4-12px
    
    confetti.style.position = 'fixed';
    confetti.style.top = '-20px';
    confetti.style.left = Math.random() * window.innerWidth + 'px';
    confetti.style.width = size + 'px';
    confetti.style.height = size + 'px';
    confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    confetti.style.pointerEvents = 'none';
    confetti.style.zIndex = '9999';
    confetti.style.animation = `confettifall 4s linear forwards`;
    
    if (shape === 'circle') {
      confetti.style.borderRadius = '50%';
    } else if (shape === 'triangle') {
      confetti.style.transform = 'rotate(45deg)';
    }
    
    document.body.appendChild(confetti);
    
    setTimeout(() => {
      if (confetti.parentNode) {
        confetti.parentNode.removeChild(confetti);
      }
    }, 4000);
  },

  /**
   * Partícula de confetti por nível
   * @memberof Hooks.GoalCelebration
   */
  createLevelConfettiPiece(level) {
    const levelColors = {
      legendary: ['#FFD700', '#FFA500', '#FF69B4', '#9932CC'],
      epic: ['#FF6347', '#FF4500', '#FF1493', '#FF8C00'],
      major: ['#4169E1', '#00BFFF', '#1E90FF', '#6495ED'],
      standard: ['#32CD32', '#00FF7F', '#98FB98', '#90EE90'],
      minor: ['#C0C0C0', '#A9A9A9', '#D3D3D3', '#DCDCDC']
    };

    const colors = levelColors[level] || levelColors.standard;
    const confetti = document.createElement('div');
    const size = level === 'legendary' ? Math.random() * 12 + 6 : Math.random() * 8 + 4;
    
    confetti.style.position = 'fixed';
    confetti.style.top = '-20px';
    confetti.style.left = Math.random() * window.innerWidth + 'px';
    confetti.style.width = size + 'px';
    confetti.style.height = size + 'px';
    confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    confetti.style.borderRadius = '50%';
    confetti.style.pointerEvents = 'none';
    confetti.style.zIndex = '9999';
    confetti.style.animation = `confettifall ${3 + Math.random() * 2}s linear forwards`;
    confetti.style.boxShadow = level === 'legendary' ? '0 0 20px rgba(255, 215, 0, 0.8)' : 'none';
    
    document.body.appendChild(confetti);
    
    setTimeout(() => {
      if (confetti.parentNode) {
        confetti.parentNode.removeChild(confetti);
      }
    }, 5000);
  },

  /**
   * Efeito de fogos de artifício para celebrações épicas
   * @memberof Hooks.GoalCelebration
   */
  createFireworks() {
    // Simula fogos de artifício com explosões radiais
    for (let i = 0; i < 5; i++) {
      setTimeout(() => {
        this.createFireworkExplosion();
      }, i * 800);
    }
  },

  /**
   * Cria uma explosão de fogos de artifício
   * @memberof Hooks.GoalCelebration
   */
  createFireworkExplosion() {
    const centerX = Math.random() * window.innerWidth;
    const centerY = Math.random() * (window.innerHeight / 2) + 50;
    
    // Cria partículas em todas as direções
    for (let i = 0; i < 20; i++) {
      const angle = (i / 20) * Math.PI * 2;
      const velocity = 100 + Math.random() * 100;
      
      this.createFireworkParticle(centerX, centerY, angle, velocity);
    }
  },

  /**
   * Cria uma partícula de fogo de artifício
   * @memberof Hooks.GoalCelebration
   */
  createFireworkParticle(startX, startY, angle, velocity) {
    const particle = document.createElement('div');
    const colors = ['#FFD700', '#FF6B35', '#F7931E', '#FFE15D', '#FF69B4'];
    
    particle.style.position = 'fixed';
    particle.style.left = startX + 'px';
    particle.style.top = startY + 'px';
    particle.style.width = '4px';
    particle.style.height = '4px';
    particle.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    particle.style.borderRadius = '50%';
    particle.style.pointerEvents = 'none';
    particle.style.zIndex = '9999';
    particle.style.boxShadow = '0 0 10px currentColor';
    
    document.body.appendChild(particle);
    
    // Anima a partícula
    let currentX = startX;
    let currentY = startY;
    let currentVelocity = velocity;
    const gravity = 200; // pixels/s²
    const startTime = performance.now();
    
    const animate = (currentTime) => {
      const elapsed = (currentTime - startTime) / 1000; // em segundos
      
      currentX = startX + Math.cos(angle) * velocity * elapsed;
      currentY = startY + Math.sin(angle) * velocity * elapsed + 0.5 * gravity * elapsed * elapsed;
      currentVelocity -= gravity * elapsed;
      
      particle.style.left = currentX + 'px';
      particle.style.top = currentY + 'px';
      
      // Fade out
      const opacity = Math.max(0, 1 - elapsed / 2);
      particle.style.opacity = opacity;
      
      if (elapsed < 2 && currentY < window.innerHeight) {
        requestAnimationFrame(animate);
      } else {
        if (particle.parentNode) {
          particle.parentNode.removeChild(particle);
        }
      }
    };
    
    requestAnimationFrame(animate);
  },

  /**
   * Retorna a duração do toast baseada no nível
   * @memberof Hooks.GoalCelebration
   */
  getToastDuration(level) {
    const durations = {
      legendary: 10000, // 10 segundos
      epic: 8000,       // 8 segundos
      major: 6000,      // 6 segundos
      standard: 4000,   // 4 segundos
      minor: 3000       // 3 segundos
    };
    
    return durations[level] || 4000;
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

// Event listener para limpar o input de mensagem
window.addEventListener("phx:clear-message-input", () => {
  const messageInput = document.getElementById("message-input");
  if (messageInput) {
    messageInput.value = "";
    messageInput.focus();
  }
})

// Event listener para marcar mensagens como lidas quando ficam visíveis
window.addEventListener("phx:mark-messages-as-read", (e) => {
  const { order_id } = e.detail;
  if (order_id) {
    // Disparar evento no LiveView para marcar mensagens como lidas
    window.dispatchEvent(new CustomEvent("phx:mark_messages_read", {
      detail: { order_id }
    }));
  }
})

// Event listener para notificações de som
window.addEventListener("phx:play_read_sound", (e) => {
  const { sound_type, count } = e.detail;
  
  // Só reproduzir som se o usuário permitiu notificações
  if (localStorage.getItem('sound_enabled') !== 'false') {
    let audioFile = '/audio/message_read.mp3';
    
    switch(sound_type) {
      case 'bulk_read':
        audioFile = '/audio/bulk_read.mp3';
        break;
      case 'bulk_read_many':
        audioFile = '/audio/bulk_read_many.mp3';
        break;
      default:
        audioFile = '/audio/message_read.mp3';
    }
    
    try {
      const audio = new Audio(audioFile);
      audio.volume = 0.3; // Volume baixo para não incomodar
      audio.play().catch(console.warn); // Falha silenciosa se não conseguir reproduzir
      
      // Log para debug (remover em produção)
      console.log(`Som reproduzido: ${sound_type}${count ? ` (${count} mensagens)` : ''}`);
    } catch (error) {
      console.warn('Erro ao reproduzir som de notificação:', error);
    }
  }
})

// Event listener para bulk read success
window.addEventListener("phx:bulk-read-success", (e) => {
  const { count } = e.detail;
  
  // Mostrar feedback visual
  const notification = document.createElement('div');
  notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded-lg shadow-lg z-50 animate-pulse';
  notification.textContent = `${count} mensagens marcadas como lidas`;
  document.body.appendChild(notification);
  
  // Remover após 3 segundos
  setTimeout(() => {
    notification.remove();
  }, 3000);
  
  // Scroll para o fim da conversa
  const messagesContainer = document.getElementById('messages');
  if (messagesContainer) {
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

