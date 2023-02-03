let addChart = () => $('<div/>').appendTo('#charts')[0]

function chartFrom(url) {
  $.ajax({
    url: url,
    success: function(result) {
      let {data, title} = result;
      let {x, y, type} = data;
      y = y.map(parseFloat);

      Plotly.newPlot(addChart(), [{x, y, title, type}], {title});
    }
  });
}
function ohlcChartFrom(url) {
  $.ajax({
    url: url,
    success: function(result) {
      let {data, title} = result;
      let {x, open, high, low, close, type} = data;
      open = open.map(parseFloat);
      high = high.map(parseFloat);
      low = low.map(parseFloat);
      close = close.map(parseFloat);

      var layout = {
        title: title,
        dragmode: 'zoom',
        margin: { r: 10, t: 25, b: 40, l: 60 },
        showlegend: false,
        xaxis: {
          autorange: true,
          domain: [0, 1],
          title: 'Date',
          type: 'date'
        },
        yaxis: {
          autorange: true,
          domain: [0, 1],
          type: 'linear'
        }
      };

      ohlc = {x, open, high, low, close, type};
      Plotly.newPlot(addChart(), [ohlc], layout);
    }
  });
};

$( document ).ready(function() {
  chartFrom("/daily_close_price");
  ohlcChartFrom('/candlestick_1m');
  ohlcChartFrom('/candlestick_1h');
  ohlcChartFrom('/candlestick_1d');
});

