/**
 * @fileoverview Arquivo de teste para implementação de gráficos ECharts
 * Demonstra a criação de um gráfico gauge usando a biblioteca ECharts
 * @author JuruConnect Team
 * @version 1.0.0
 */

import * as echarts from 'echarts';

/**
 * Inicializa um gráfico de gauge de demonstração usando ECharts
 * Aguarda o carregamento completo do DOM antes de criar o gráfico
 * @function
 * @global
 */
document.addEventListener('DOMContentLoaded', function () {
  const chartDom = document.getElementById('echarts-demo');
  if (!chartDom) return;
  
  /**
   * Instância do gráfico ECharts
   * @type {echarts.ECharts}
   */
  const myChart = echarts.init(chartDom);
  
  /**
   * Configuração do gráfico gauge
   * @type {echarts.EChartsOption}
   */
  const option = {
    tooltip: {
      formatter: '{a} <br/>{b} : {c}%'
    },
    series: [
      {
        name: 'Pressure',
        type: 'gauge',
        progress: {
          show: true
        },
        detail: {
          valueAnimation: true,
          formatter: '{value}'
        },
        data: [
          {
            value: 50,
            name: 'SCORE'
          }
        ]
      }
    ]
  };
  
  myChart.setOption(option);
}); 