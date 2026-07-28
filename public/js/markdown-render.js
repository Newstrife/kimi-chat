/*
 * 聊天消息 Markdown 渲染（本地离线版）。
 * 依赖同目录引入的 /vendor/marked.min.js 与 /vendor/purify.min.js。
 * 用法：renderMarkdownToHtml(markdownText) -> 安全的 HTML 字符串。
 */
(function (global) {
  'use strict';

  if (typeof marked !== 'undefined' && marked.setOptions) {
    marked.setOptions({
      gfm: true,   // GitHub Flavored Markdown：表格、删除线等
      breaks: true // 单个换行也渲染为 <br>，贴合聊天场景
    });
  }

  /**
   * 将 Markdown 文本渲染为经过 XSS 过滤的安全 HTML。
   * @param {string} text Markdown 源文本
   * @returns {string} 可直接赋值给 innerHTML 的安全 HTML
   */
  function renderMarkdownToHtml(text) {
    var src = text == null ? '' : String(text);
    var html = marked.parse(src);
    return DOMPurify.sanitize(html, {
      USE_PROFILES: { html: true }
    });
  }

  global.renderMarkdownToHtml = renderMarkdownToHtml;
})(window);
