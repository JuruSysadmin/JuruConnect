import * as echarts from 'echarts';

document.addEventListener('DOMContentLoaded', function () {
  const chartDom = document.getElementById('echarts-demo');
  if (!chartDom) return;
  const myChart = echarts.init(chartDom);
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