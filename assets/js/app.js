/**
 * @fileoverview Arquivo principal do Phoenix LiveView com hooks para gráficos e interações
 * @author JuruConnect Team
 * @version 1.0.0
 */

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import hooks from "./hooks"

/**
 * Token CSRF obtido do meta tag
 * @type {string}
 */
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Declarar variável global do LiveSocket
let liveSocket

/**
 * Coleção de hooks do Phoenix LiveView
 * @type {Object}
 */
let Hooks = {
  ...hooks
}

Hooks.AutoHideFlash = {
  mounted() {
    setTimeout(() => {
      this.el.style.display = "none";
    }, 4000);
  }
}

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

// Inicializar o LiveSocket com todas as configurações
liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Conectar apenas uma vez
liveSocket.connect()
window.liveSocket = liveSocket