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
import "./pwa"

let Hooks = {}

Hooks.ChatHook = ChatHook

// Hooks for charts
Hooks.Chart = {
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

// Hooks for gauge charts
Hooks.GaugeChart = {
  mounted() {
    this.initChart();
    this.handleEvent("update-gauge", (data) => {
      this.updateChart(data.value);
    });
  },
  
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
  
  updateChart(value) {
    if (this.chart) {
      this.chart.data.datasets[0].data = [value, 100 - value];
      this.chart.data.datasets[0].backgroundColor[0] = this.getColor(value);
      this.chart.update('active');
    }
  },
  
  getColor(value) {
    if (value >= 100) return '#059669'; // Green-600
    if (value >= 80) return '#10B981';  // Green-500
    if (value >= 60) return '#F59E0B';  // Yellow-500
    if (value >= 40) return '#F97316';  // Orange-500
    return '#EF4444'; // Red-500
  },
  
  updated() {
    const value = parseFloat(this.el.dataset.value) || 0;
    this.updateChart(value);
  }
}

// Hook para celebração de meta atingida
Hooks.GoalCelebration = {
  mounted() {
    this.handleEvent("goal-achieved", (data) => {
      this.celebrate(data);
    });
  },
  
  celebrate(data) {
    // Efeito sonoro (opcional - só funciona com interação do usuário)
    this.playSound();
    
    // Mostra toast notification
    this.showToast(data.store_name, data.achieved);
    
    // Efeito de confetti
    this.createConfetti();
  },
  
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
      console.log('Audio not available');
    }
  },
  
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
  
  createConfetti() {
    // Cria partículas de confetti
    for (let i = 0; i < 50; i++) {
      setTimeout(() => {
        this.createConfettiPiece();
      }, i * 50);
    }
  },
  
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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
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

