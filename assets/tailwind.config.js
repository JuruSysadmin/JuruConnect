/**
 * @fileoverview Configuração personalizada do Tailwind CSS para o projeto JuruConnect
 * Inclui plugins para LiveView e formulários
 * @author JuruConnect Team
 * @version 1.0.0
 * @see {@link https://tailwindcss.com/docs/configuration}
 */

// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const colors = require('tailwindcss/colors');
const plugin = require('tailwindcss/plugin');

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
    './js/**/*.js',
    '../lib/*_web.ex',
    '../lib/*_web/**/*.*ex',
    '../deps/phoenix_live_view/**/*.*ex',
    '../lib/*_web/components/*.ex',
    '../lib/*_web/components/**/*.ex',
    '../lib/*_web/live/**/*.ex',
    '../lib/*_web/controllers/**/*.ex',
    '../lib/*_web/templates/**/*.*eex',
    '../lib/*_web/components/layouts/**/*.*eex',
    '../lib/*_web/components/**/*.*eex'
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
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]))
  ]
}
