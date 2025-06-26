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

let Hooks = {}

Hooks.GaugeChart = {
  mounted() {
    this.createChart(this.el.dataset.value);

    this.handleEvent("update-gauge", ({value}) => {
        this.updateChart(value);
    })
  },

  updateChart(value) {
    const percentage = Math.min(value, 100);
    this.chart.data.datasets[0].data[0] = percentage;
    this.chart.data.datasets[0].data[1] = 100 - percentage;
    this.chart.update('none'); 
  },

  createChart(initialValue) {
    const value = Math.min(initialValue, 100);

    const data = {
      datasets: [{
        data: [value, 100 - value],
        backgroundColor: [
          '#3b82f6', 
          '#e5e7eb'  
        ],
        borderColor: [
            '#3b82f6',
            '#e5e7eb'
        ],
        borderWidth: 0,
        hoverBorderWidth: 0,

      }]
    };

    const config = {
      type: 'doughnut',
      data: data,
      options: {
        responsive: true,
        rotation: -90,
        circumference: 180,
        cutout: '80%',
        events: [],
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            enabled: false
          },
        },
      }
    };

    this.chart = new Chart(
      this.el,
      config
    );
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

