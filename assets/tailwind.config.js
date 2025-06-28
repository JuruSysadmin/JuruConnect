/**
 * @fileoverview Configuração personalizada do Tailwind CSS para o projeto JuruConnect
 * Inclui plugins para LiveView, formulários e ícones Heroicons
 * @author JuruConnect Team
 * @version 1.0.0
 * @see {@link https://tailwindcss.com/docs/configuration}
 */

// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

/**
 * Configuração principal do Tailwind CSS
 * @type {import('tailwindcss').Config}
 */
module.exports = {
  /**
   * Arquivos a serem observados para classes CSS
   * @type {string[]}
   */
  content: [
    "./js/**/*.js",
    "../lib/app_web.ex",
    "../lib/app_web/**/*.{ex,heex}"
  ],
  
  /**
   * Configurações do tema
   * @type {Object}
   */
  theme: {
    extend: {
      /**
       * Cores personalizadas do projeto
       * @type {Object}
       */
      colors: {
        brand: "#FD4F00",
      }
    },
  },
  
  /**
   * Plugins do Tailwind CSS
   * @type {Array}
   */
  plugins: [
    require("@tailwindcss/forms"),
    
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    
    /**
     * Plugin para variantes de loading do Phoenix LiveView
     * Adiciona suporte para estados de loading em clicks
     */
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    
    /**
     * Plugin para variantes de loading do Phoenix LiveView
     * Adiciona suporte para estados de loading em submits de formulário
     */
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    
    /**
     * Plugin para variantes de loading do Phoenix LiveView
     * Adiciona suporte para estados de loading em mudanças de formulário
     */
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    
    /**
     * Plugin para incorporar ícones Heroicons como classes CSS
     * Gera automaticamente classes para todos os ícones disponíveis
     * @param {Object} helpers - Helpers do Tailwind CSS
     * @param {Function} helpers.matchComponents - Função para criar componentes
     * @param {Function} helpers.theme - Função para acessar valores do tema
     */
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      
      matchComponents({
        /**
         * Componente para ícones Heroicons
         * @param {Object} params - Parâmetros do ícone
         * @param {string} params.name - Nome do ícone
         * @param {string} params.fullPath - Caminho completo para o arquivo SVG
         * @returns {Object} Estilos CSS para o ícone
         */
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
