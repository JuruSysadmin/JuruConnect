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
import annotationPlugin from 'chartjs-plugin-annotation';
import 'chartjs-gauge';
Chart.register(annotationPlugin);

/**
 * Coleção de hooks do Phoenix LiveView
 * @type {Object}
 */
let Hooks = {}

// Chart hook já definido como const ChartHook mais abaixo

// WhatsAppAudioPlayer hook - sem definição duplicada

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
    if (value >= 60) return '#60A5FA';  // Blue-400
    if (value >= 40) return '#3B82F6';  // Blue-500
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
            '#EAEAEA'
          ],
          borderWidth: 0,
          borderRadius: 8
        }]
      },
      options: {
        aspectRatio: 2,
        circumference: 180,
        rotation: -90,
        cutout: '75%',
        plugins: {
          legend: { display: false },
          tooltip: { enabled: false },
          annotation: {
            annotations: {
              label: {
                type: 'doughnutLabel',
                content: [
                  value.toFixed(1) + ' %',
                  'do objetivo mensal'
                ],
                drawTime: 'beforeDraw',
                position: { y: '-50%' },
                font: [{ size: 32, weight: 'bold' }, { size: 14 }],
                color: ['#2563eb', 'grey']
              }
            }
          }
        },
        animation: {
          animateRotate: true,
          duration: 1500,
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
      this.chart.data.datasets[0].data = [value, 100 - value];
      this.chart.data.datasets[0].backgroundColor[0] = this.getColor(value);
      // Atualiza o label do annotation
      if (this.chart.options.plugins && this.chart.options.plugins.annotation && this.chart.options.plugins.annotation.annotations && this.chart.options.plugins.annotation.annotations.label) {
        this.chart.options.plugins.annotation.annotations.label.content = [
          value.toFixed(1) + ' %',
          'do objetivo mensal'
        ];
      }
      this.chart.update('active');
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
    if (value >= 60) return '#60A5FA';  // Blue-400
    if (value >= 40) return '#1E3A8A';  // Blue-900 (mais escuro)
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
    this.handleEvent("goal-achieved", (data) => this.celebrate(data))
    this.handleEvent("goal-achieved-multiple", (data) => this.celebrateMultiple(data))
    this.handleEvent("goal-achieved-real", (data) => this.celebrateReal(data))
  },

  /**
   * Executa a celebração completa com som, toast e confetti
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da meta atingida
   * @param {string} data.store_name - Nome da loja
   * @param {string} data.achieved - Valor atingido formatado
   */
  celebrate(data) {
    this.playSound()
    this.showToast(data.store_name, data.achieved)
    this.createConfetti()
  },

  /**
   * Reproduz um som de sucesso usando Web Audio API
   * @memberof Hooks.GoalCelebration
   */
  playSound() {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)()
      const oscillator = audioContext.createOscillator()
      const gainNode = audioContext.createGain()

      oscillator.connect(gainNode)
      gainNode.connect(audioContext.destination)

      oscillator.frequency.setValueAtTime(800, audioContext.currentTime)
      oscillator.frequency.exponentialRampToValueAtTime(1200, audioContext.currentTime + 0.1)

      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5)

      oscillator.start(audioContext.currentTime)
      oscillator.stop(audioContext.currentTime + 0.5)
    } catch (e) {
      console.log("Audio not available")
    }
  },

  /**
   * Exibe uma notificação toast no canto da tela
   * @memberof Hooks.GoalCelebration
   * @param {string} storeName - Nome da loja
   * @param {string} achieved - Valor atingido formatado
   */
  showToast(storeName, achieved) {
    const toast = document.createElement('div')
    toast.className = 'fixed top-4 right-4 bg-green-500 text-white p-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300'
    toast.innerHTML = `
      <div class="flex items-center space-x-2">
        <span class="text-2xl">🎉</span>
        <div>
          <div class="font-bold">Meta Atingida!</div>
          <div class="text-sm">${storeName}</div>
          <div class="text-xs">${achieved}</div>
        </div>
      </div>
    `

    document.body.appendChild(toast)

    setTimeout(() => toast.classList.remove('translate-x-full'), 100)

    setTimeout(() => {
      toast.classList.add('translate-x-full')
      setTimeout(() => document.body.removeChild(toast), 300)
    }, 4000)
  },

  /**
   * Cria efeito de confetti com múltiplas partículas
   * @memberof Hooks.GoalCelebration
   */
  createConfetti() {
    for (let i = 0; i < 50; i++) {
      setTimeout(() => this.createConfettiPiece(), i * 50)
    }
  },

  /**
   * Cria uma única partícula de confetti animada
   * @memberof Hooks.GoalCelebration
   */
  createConfettiPiece() {
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
    const confetti = document.createElement('div')

    confetti.style.position = 'fixed'
    confetti.style.top = '-10px'
    confetti.style.left = Math.random() * window.innerWidth + 'px'
    confetti.style.width = '10px'
    confetti.style.height = '10px'
    confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)]
    confetti.style.borderRadius = '50%'
    confetti.style.pointerEvents = 'none'
    confetti.style.zIndex = '9999'
    confetti.style.animation = 'confettifall 3s linear forwards'

    document.body.appendChild(confetti)

    setTimeout(() => {
      if (confetti.parentNode) confetti.parentNode.removeChild(confetti)
    }, 3000)
  },

  /**
   * Celebração múltipla com efeitos mais intensos
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da celebração múltipla
   */
  celebrateMultiple(data) {
    this.celebrate(data)
  },

  /**
   * Celebração real baseada em dados da API com níveis diferentes
   * @memberof Hooks.GoalCelebration
   * @param {Object} data - Dados da celebração real
   */
  celebrateReal(data) {
    this.celebrate(data)
  }
}

/**
 * Token CSRF obtido do meta tag
 * @type {string}
 */
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Declarar variável global do LiveSocket
let liveSocket

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

// Removi a duplicação - liveSocket.connect() será chamado apenas uma vez no final

const AudioRecorderHook = {
  mounted() {
    this.initializeAudioRecorder()
    this.setupAudioEventHandlers()
    this.checkAudioSupport()
  },

  initializeAudioRecorder() {
    this.isRecording = false
    this.mediaRecorder = null
    this.audioChunks = []
    this.audioStream = null
  },

  setupAudioEventHandlers() {
    this.handleEvent("start_audio_recording", () => this.startAudioRecording())
    this.handleEvent("stop_audio_recording", () => this.stopAudioRecording())
    this.handleEvent("play_audio_message", (data) => this.playAudioMessage(data))
  },

  checkAudioSupport() {
    const isSupported = this.isMediaRecordingSupported()
    const isSecure = this.isSecureContext()

    this.updateAudioButtonState(isSupported && isSecure)

    if (!isSupported) {
      console.warn("Audio recording not supported in this browser")
    }

    if (!isSecure) {
      console.warn("Audio recording requires secure context (HTTPS)")
    }
  },

  updateAudioButtonState(isEnabled) {
    const recordButton = document.getElementById('audio-record-button')
    const recordIcon = document.getElementById('audio-record-icon')

    if (recordButton && recordIcon) {
      if (isEnabled) {
        recordButton.disabled = false
        recordButton.classList.remove('opacity-50', 'cursor-not-allowed')
        recordButton.classList.add('hover:bg-gray-500')
        recordButton.title = 'Gravar áudio'
      } else {
        recordButton.disabled = true
        recordButton.classList.add('opacity-50', 'cursor-not-allowed')
        recordButton.classList.remove('hover:bg-gray-500')
        recordButton.title = 'Gravação de áudio não disponível (requer HTTPS)'
      }
    }
  },

  async startAudioRecording() {
    try {
      // Verificar se a API de mídia está disponível
      if (!this.isMediaRecordingSupported()) {
        throw new Error("Gravação de áudio não suportada neste navegador ou contexto")
      }

      // Verificar se está em contexto seguro (HTTPS)
      if (!this.isSecureContext()) {
        throw new Error("Gravação de áudio requer conexão segura (HTTPS)")
      }

      this.audioStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      })

      this.mediaRecorder = new MediaRecorder(this.audioStream, {
        mimeType: this.getSupportedMimeType()
      })

      this.audioChunks = []
      this.setupMediaRecorderHandlers()

      this.mediaRecorder.start(1000)
      this.isRecording = true

      this.pushEvent("audio_recording_started", {})
      this.updateRecordingUI(true)

    } catch (error) {
      console.error("Error starting audio recording:", error)
      this.pushEvent("audio_recording_error", { error: this.getErrorMessage(error) })
    }
  },

  setupMediaRecorderHandlers() {
    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        this.audioChunks.push(event.data)
      }
    }

    this.mediaRecorder.onstop = () => {
      this.processRecordedAudio()
    }
  },

  stopAudioRecording() {
    if (this.mediaRecorder && this.isRecording) {
      this.mediaRecorder.stop()
      this.audioStream.getTracks().forEach(track => track.stop())
      this.isRecording = false
      this.updateRecordingUI(false)
    }
  },

  async processRecordedAudio() {
    const audioBlob = new Blob(this.audioChunks, {
      type: this.getSupportedMimeType()
    })

    const audioDuration = await this.calculateAudioDuration(audioBlob)
    const audioBase64 = await this.convertBlobToBase64(audioBlob)

    this.pushEvent("audio_recorded", {
      audio_data: audioBase64,
      duration: audioDuration,
      mime_type: this.getSupportedMimeType()
    })
  },

  getSupportedMimeType() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/wav'
    ]

    return types.find(type => MediaRecorder.isTypeSupported(type)) || 'audio/webm'
  },

  async calculateAudioDuration(blob) {
    return new Promise((resolve) => {
      const audio = new Audio()
      audio.onloadedmetadata = () => {
        resolve(Math.round(audio.duration))
      }
      audio.src = URL.createObjectURL(blob)
    })
  },

  async convertBlobToBase64(blob) {
    return new Promise((resolve) => {
      const reader = new FileReader()
      reader.onloadend = () => resolve(reader.result.split(',')[1])
      reader.readAsDataURL(blob)
    })
  },

  playAudioMessage(data) {
    const audio = new Audio(data.audio_url)
    audio.play().catch(error => {
      console.error("Error playing audio:", error)
    })
  },

  updateRecordingUI(isRecording) {
    const recordButton = document.getElementById('audio-record-button')
    const recordIcon = document.getElementById('audio-record-icon')

    if (recordButton && recordIcon) {
      if (isRecording) {
        recordButton.classList.add('bg-red-500', 'animate-pulse')
        recordButton.classList.remove('bg-gray-400')
        recordIcon.textContent = '⏹️'
      } else {
        recordButton.classList.remove('bg-red-500', 'animate-pulse')
        recordButton.classList.add('bg-gray-400')
        recordIcon.textContent = '🎙️'
      }
    }
  },

  // Verificações de compatibilidade e segurança
  isMediaRecordingSupported() {
    return !!(navigator.mediaDevices &&
              navigator.mediaDevices.getUserMedia &&
              window.MediaRecorder &&
              MediaRecorder.isTypeSupported)
  },

  isSecureContext() {
    return window.isSecureContext ||
           location.protocol === 'https:' ||
           location.hostname === 'localhost' ||
           location.hostname === '127.0.0.1'
  },

  getErrorMessage(error) {
    const errorMap = {
      'NotAllowedError': 'Permissão de microfone negada. Por favor, autorize o acesso ao microfone.',
      'NotFoundError': 'Nenhum microfone encontrado. Verifique se há um microfone conectado.',
      'NotReadableError': 'Erro ao acessar o microfone. Pode estar sendo usado por outro aplicativo.',
      'OverconstrainedError': 'Configurações de áudio não suportadas pelo dispositivo.',
      'SecurityError': 'Gravação de áudio bloqueada por política de segurança.',
      'AbortError': 'Gravação de áudio foi interrompida.',
      'TypeError': 'Erro de configuração do gravador de áudio.'
    }

    if (error.name && errorMap[error.name]) {
      return errorMap[error.name]
    }

    // Mensagens específicas para problemas comuns
    if (error.message.includes('getUserMedia')) {
      return 'Funcionalidade de gravação não disponível. Use HTTPS ou localhost.'
    }

    if (error.message.includes('mediaDevices')) {
      return 'Navegador não suporta gravação de áudio ou conexão não é segura.'
    }

    return error.message || 'Erro desconhecido ao gravar áudio'
  }
}

const ChatHook = {
  mounted() {
    this.setupChatEventHandlers()
    this.scrollToBottom()
    this.setupImagePreview()
  },

  updated() {
    this.scrollToBottom()
  },

  setupChatEventHandlers() {
    this.handleEvent("scroll-to-bottom", () => this.scrollToBottom())
    this.handleEvent("mention-notification", (data) => this.showMentionNotification(data))
    this.handleEvent("desktop-notification", (data) => this.showDesktopNotification(data))
    this.handleEvent("clear-message-input", () => this.clearMessageInput())
  },

  setupImagePreview() {
    // Configurar preview de imagem manual
    const imageInput = this.el.querySelector('input[type="file"]')
    if (imageInput) {
      imageInput.addEventListener('change', (e) => this.handleImagePreview(e))
    }
  },

  handleImagePreview(event) {
    const file = event.target.files[0]
    if (!file) return

    // Verificar se é uma imagem
    if (!file.type.startsWith('image/')) return

    // Criar URL temporária da imagem
    const imageUrl = URL.createObjectURL(file)

    // Procurar por elemento de preview existente ou criar um novo
    let previewContainer = this.el.querySelector('.js-manual-image-preview')
    if (!previewContainer) {
      previewContainer = this.createPreviewContainer()
    }

    // Atualizar preview
    const previewImg = previewContainer.querySelector('.js-preview-image')
    if (previewImg) {
      previewImg.src = imageUrl
      previewImg.style.display = 'block'
    }

    // Limpar URL quando não precisar mais
    setTimeout(() => URL.revokeObjectURL(imageUrl), 60000)
  },

  createPreviewContainer() {
    const container = document.createElement('div')
    container.className = 'js-manual-image-preview hidden'
    container.innerHTML = `
      <img class="js-preview-image w-16 h-16 object-cover rounded-lg border-2 border-blue-200 shadow-sm" style="display: none" alt="Preview da imagem">
    `

    // Tentar inserir antes do live_img_preview existente
    const existingPreview = this.el.querySelector('.live_img_preview, [data-phx-entry-ref]')
    if (existingPreview && existingPreview.parentNode) {
      existingPreview.parentNode.insertBefore(container, existingPreview)
    }

    return container
  },

  scrollToBottom() {
    const container = document.getElementById("messages")
    if (container) {
      setTimeout(() => {
        container.scrollTop = container.scrollHeight
      }, 50)
    }
  },

  showMentionNotification(data) {
    if (Notification.permission === "granted") {
      new Notification(`Menção de ${data.sender_name}`, {
        body: data.text,
        icon: "/images/chat-icon.png"
      })
    }
  },

  showDesktopNotification(data) {
    if (Notification.permission === "granted") {
      new Notification(data.title, {
        body: data.body,
        icon: data.icon || "/images/notification-icon.png"
      })
    }
  },

  clearMessageInput() {
    const input = document.getElementById("message-input")
    if (input) {
      input.value = ""
    }
  }
}

const GoalCelebrationHook = {
  mounted() {
    this.handleEvent("goal-achieved", (data) => this.celebrate(data))
    this.handleEvent("goal-achieved-multiple", (data) => this.celebrateMultiple(data))
    this.handleEvent("goal-achieved-real", (data) => this.celebrateReal(data))
  },

  celebrate(data) {
    this.playSound()
    this.showToast(data.store_name, data.achieved)
    this.createConfetti()
  },

  playSound() {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)()
      const oscillator = audioContext.createOscillator()
      const gainNode = audioContext.createGain()

      oscillator.connect(gainNode)
      gainNode.connect(audioContext.destination)

      oscillator.frequency.setValueAtTime(800, audioContext.currentTime)
      oscillator.frequency.exponentialRampToValueAtTime(1200, audioContext.currentTime + 0.1)

      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5)

      oscillator.start(audioContext.currentTime)
      oscillator.stop(audioContext.currentTime + 0.5)
    } catch (e) {
      console.log("Audio not available")
    }
  },

  showToast(storeName, achieved) {
    const toast = document.createElement('div')
    toast.className = 'fixed top-4 right-4 bg-green-500 text-white p-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300'
    toast.innerHTML = `
      <div class="flex items-center space-x-2">
        <span class="text-2xl">🎉</span>
        <div>
          <div class="font-bold">Meta Atingida!</div>
          <div class="text-sm">${storeName}</div>
          <div class="text-xs">${achieved}</div>
        </div>
      </div>
    `

    document.body.appendChild(toast)
    setTimeout(() => toast.classList.remove('translate-x-full'), 100)
    setTimeout(() => {
      toast.classList.add('translate-x-full')
      setTimeout(() => document.body.removeChild(toast), 300)
    }, 4000)
  },

  createConfetti() {
    for (let i = 0; i < 50; i++) {
      setTimeout(() => this.createConfettiPiece(), i * 50)
    }
  },

  createConfettiPiece() {
    const colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
    const confetti = document.createElement('div')

    confetti.style.position = 'fixed'
    confetti.style.top = '-10px'
    confetti.style.left = Math.random() * window.innerWidth + 'px'
    confetti.style.width = '10px'
    confetti.style.height = '10px'
    confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)]
    confetti.style.borderRadius = '50%'
    confetti.style.pointerEvents = 'none'
    confetti.style.zIndex = '9999'
    confetti.style.animation = 'confettifall 3s linear forwards'

    document.body.appendChild(confetti)
    setTimeout(() => {
      if (confetti.parentNode) confetti.parentNode.removeChild(confetti)
    }, 3000)
  },

  celebrateMultiple(data) {
    this.celebrate(data)
  },

  celebrateReal(data) {
    this.celebrate(data)
  }
}

const AutoDismissFlashHook = {
  mounted() {
    const kind = this.el.dataset.kind

    if (kind === 'info') {
      this.timeout = setTimeout(() => {
        this.el.click()
      }, 4000)
    }
  },

  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
}

const ChartHook = {
  mounted() {
    const ctx = this.el.getContext('2d')
    const data = JSON.parse(this.el.dataset.chartData)

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
    })
  }
}

const GaugeChartHook = {
  mounted() {
    this.initChart()
    this.handleEvent("update-gauge", (data) => {
      this.updateChart(data.value)
    })
  },

  initChart() {
    const ctx = this.el.getContext('2d')
    const value = parseFloat(this.el.dataset.value) || 0

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
    })
  },

  updateChart(value) {
    if (this.chart) {
      this.chart.data.datasets[0].data = [value, 100 - value]
      this.chart.data.datasets[0].backgroundColor[0] = this.getColor(value)
      this.chart.update('active')
    }
  },

  getColor(value) {
    if (value >= 100) return '#059669'
    if (value >= 80) return '#10B981'
    if (value >= 60) return '#60A5FA'
    if (value >= 40) return '#3B82F6'
    return '#EF4444'
  },

  updated() {
    const value = parseFloat(this.el.dataset.value) || 0
    this.updateChart(value)
  }
}

Hooks.GaugeChartMensalPonteiro = {
  mounted() {
    this.initChart();
    this.handleEvent("update-gauge-monthly", (data) => {
      this.updateChart(data.value);
    });
  },
  initChart() {
    const ctx = this.el.getContext('2d');
    const value = parseFloat(this.el.dataset.value) || 0;
    this.chart = new Chart(ctx, {
      type: 'gauge',
      data: {
        datasets: [{
          value: value,
          minValue: 0,
          data: [100],
          backgroundColor: ['#2563eb'],
          borderWidth: 2
        }]
      },
      options: {
        needle: {
          radiusPercentage: 2,
          widthPercentage: 3.2,
          lengthPercentage: 80,
          color: 'rgba(0, 0, 0, 1)'
        },
        valueLabel: {
          display: true,
          formatter: (value) => value.toFixed(1) + ' %'
        },
        plugins: {
          legend: { display: false }
        }
      }
    });
  },
  updateChart(value) {
    if (this.chart) {
      this.chart.data.datasets[0].value = value;
      this.chart.update('active');
    }
  }
};

// Adicionar todos os hooks ao objeto Hooks
Hooks.ChatHook = ChatHook
Hooks.AudioRecorderHook = AudioRecorderHook
Hooks.GoalCelebration = GoalCelebrationHook
Hooks.AutoDismissFlash = AutoDismissFlashHook
Hooks.Chart = ChartHook
Hooks.GaugeChart = GaugeChartHook
Hooks.GaugeChartMensalPonteiro = Hooks.GaugeChartMensalPonteiro;

// Inicializar o LiveSocket com todas as configurações
liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:clear-message-input", () => {
  const messageInput = document.getElementById("message-input")
  if (messageInput) {
    messageInput.value = ""
    messageInput.focus()
  }
})

window.addEventListener("phx:mark-messages-as-read", (e) => {
  const { order_id } = e.detail
  if (order_id) {
    window.dispatchEvent(new CustomEvent("phx:mark_messages_read", {
      detail: { order_id }
    }))
  }
})

window.addEventListener("phx:bulk-read-success", (e) => {
  const { count } = e.detail

  const notification = document.createElement('div')
  notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded-lg shadow-lg z-50 animate-pulse'
  notification.textContent = `${count} mensagens marcadas como lidas`
  document.body.appendChild(notification)

  setTimeout(() => {
    notification.remove()
  }, 3000)

  const messagesContainer = document.getElementById('messages')
  if (messagesContainer) {
    messagesContainer.scrollTop = messagesContainer.scrollHeight
  }
})

// Conectar apenas uma vez
liveSocket.connect()
window.liveSocket = liveSocket

