/*
 * 聊天消息中的 ```chart 代码块渲染（Chart.js 本地离线版）。
 * 依赖：/vendor/marked.min.js、/vendor/purify.min.js（经 markdown-render.js）、/vendor/chart.umd.min.js。
 * 用法：
 *   var r = renderMessageWithCharts(markdownText); // -> { html, charts: [{canvasId, config}] }
 *   el.innerHTML = r.html;
 *   mountCharts(r.charts); // innerHTML 设置之后再调用
 *
 * chart 代码块约定（由服务端提示词约束 AI 输出）：
 *   ```chart
 *   {"type":"bar|line|pie","title":"图表标题","labels":["标签1","标签2"],"series":[{"name":"系列名","data":[1,2]}]}
 *   ```
 * bar/line 可多组 series，pie 只用一组 series。JSON 解析失败的块按普通代码块原样渲染。
 */
(function (global) {
  'use strict';

  var CHART_BLOCK_RE = /```chart\s*\n([\s\S]*?)```/g;
  var PALETTE = [
    '#4f46e5', '#059669', '#d97706', '#dc2626', '#0891b2',
    '#7c3aed', '#db2777', '#65a30d', '#ea580c', '#2563eb'
  ];

  function paletteColor(i, alpha) {
    var hex = PALETTE[i % PALETTE.length];
    if (alpha == null) return hex;
    var r = parseInt(hex.slice(1, 3), 16);
    var g = parseInt(hex.slice(3, 5), 16);
    var b = parseInt(hex.slice(5, 7), 16);
    return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
  }

  /**
   * 把我们的 JSON 格式映射为 Chart.js 配置。
   * series -> datasets（每项加 label 和 data）；pie 不需要坐标轴。
   */
  function toChartConfig(spec) {
    var type = spec.type;
    if (['bar', 'line', 'pie'].indexOf(type) === -1) type = 'bar';
    var labels = Array.isArray(spec.labels) ? spec.labels : [];
    var series = Array.isArray(spec.series) && spec.series.length ? spec.series : [{ name: '', data: [] }];
    if (type === 'pie') series = series.slice(0, 1); // pie 只用一组 series

    var datasets = series.map(function (s, i) {
      var ds = {
        label: s.name || ('系列' + (i + 1)),
        data: Array.isArray(s.data) ? s.data : []
      };
      if (type === 'pie') {
        ds.backgroundColor = labels.map(function (_, j) { return paletteColor(j, 0.85); });
        ds.borderColor = '#ffffff';
        ds.borderWidth = 1;
      } else if (type === 'line') {
        ds.borderColor = paletteColor(i);
        ds.backgroundColor = paletteColor(i, 0.15);
        ds.tension = 0.3;
        ds.fill = false;
      } else { // bar
        ds.backgroundColor = paletteColor(i, 0.75);
        ds.borderColor = paletteColor(i);
        ds.borderWidth = 1;
      }
      return ds;
    });

    var config = {
      type: type,
      data: { labels: labels, datasets: datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false, // 高度由 .chart-container 固定
        plugins: {
          title: { display: !!spec.title, text: spec.title || '' },
          legend: { display: type === 'pie' || datasets.length > 1 }
        }
      }
    };
    if (type !== 'pie') {
      config.options.scales = { y: { beginAtZero: true } };
    }
    return config;
  }

  /**
   * 从 Markdown 中提取 ```chart 块，成功解析的替换为占位符，其余走 Markdown 渲染，
   * 最后把占位符替换为 <div class="chart-container"><canvas ...></canvas></div>。
   * @param {string} markdownText 原始 Markdown 文本
   * @returns {{html: string, charts: Array<{canvasId: string, config: object}>}}
   */
  function renderMessageWithCharts(markdownText) {
    var src = markdownText == null ? '' : String(markdownText);
    var charts = [];
    var uid = 0;

    var withPlaceholders = src.replace(CHART_BLOCK_RE, function (match, jsonText) {
      var spec;
      try {
        spec = JSON.parse(jsonText.trim());
      } catch (e) {
        return match; // 解析失败：保留原样，当普通代码块渲染
      }
      var canvasId = 'chart-canvas-' + Date.now().toString(36) + '-' + (uid++);
      charts.push({ canvasId: canvasId, config: toChartConfig(spec) });
      return '%%CHART_' + (charts.length - 1) + '%%';
    });

    var html = global.renderMarkdownToHtml(withPlaceholders);

    charts.forEach(function (c, i) {
      // 占位符可能被 marked 包进 <p>，整体替换避免 div 嵌在 p 里
      var tag = '<div class="chart-container"><canvas id="' + c.canvasId + '"></canvas></div>';
      html = html
        .split('<p>%%CHART_' + i + '%%</p>').join(tag)
        .split('%%CHART_' + i + '%%').join(tag);
    });

    return { html: html, charts: charts };
  }

  /**
   * 在 innerHTML 设置之后调用：对每个 canvas 挂载 Chart.js 图表。
   * @param {Array<{canvasId: string, config: object}>} charts
   */
  function mountCharts(charts) {
    if (!charts || !charts.length || typeof Chart === 'undefined') return;
    charts.forEach(function (c) {
      var canvas = document.getElementById(c.canvasId);
      if (!canvas) return;
      try {
        new Chart(canvas.getContext('2d'), c.config);
      } catch (e) {
        // 单个图表失败不影响其余内容
        if (global.console && console.warn) console.warn('chart 挂载失败', e);
      }
    });
  }

  global.renderMessageWithCharts = renderMessageWithCharts;
  global.mountCharts = mountCharts;
})(window);
