import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket

let Hooks = {}

Hooks.AutoDismissFlash = {
  mounted() {
    setTimeout(() => {
      this.el.style.display = "none";
    }, 4000);
  }
}

Hooks.AutoHideFlash = Hooks.AutoDismissFlash

liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

liveSocket.connect()