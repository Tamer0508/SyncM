const fs = require('fs');
const path = require('path');
const express = require('express');

const router = express.Router();
const logger = require('../infrastructure/logger');

const DOCUMENTS = {
  privacy: {
    file: 'privacy_policy.md',
    title: 'Политика конфиденциальности SyncM',
  },
  terms: {
    file: 'terms_of_use.md',
    title: 'Условия использования SyncM',
  },
};

const LEGAL_DIR = path.join(__dirname, '..', '..', 'legal');

const cache = new Map();

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[ch]);
}

function renderMarkdown(source) {
  const html = [];
  let inList = false;

  const closeList = () => {
    if (inList) {
      html.push('</ul>');
      inList = false;
    }
  };

  const inline = (text) =>
    escapeHtml(text).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  for (const rawLine of source.split('\n')) {
    const line = rawLine.trimEnd();

    if (!line) {
      closeList();
      continue;
    }

    if (line.startsWith('---')) {
      closeList();
      html.push('<hr>');
      continue;
    }

    const heading = line.match(/^(#{1,3})\s+(.*)$/);
    if (heading) {
      closeList();
      const level = heading[1].length;
      html.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      continue;
    }

    if (/^[-*]\s+/.test(line)) {
      if (!inList) {
        html.push('<ul>');
        inList = true;
      }
      html.push(`<li>${inline(line.replace(/^[-*]\s+/, ''))}</li>`);
      continue;
    }

    closeList();
    html.push(`<p>${inline(line)}</p>`);
  }

  closeList();
  return html.join('\n');
}

function page(title, body) {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0;
    padding: 32px 20px 64px;
    background: #121212;
    color: #a6a6a6;
    font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  }
  main { max-width: 720px; margin: 0 auto; }
  h1, h2, h3 { color: #ededed; line-height: 1.3; margin: 32px 0 12px; }
  h1 { font-size: 28px; }
  h2 { font-size: 21px; }
  h3 { font-size: 17px; }
  h1:first-child { margin-top: 0; }
  strong { color: #ededed; font-weight: 600; }
  ul { padding-left: 20px; }
  li { margin: 6px 0; }
  hr { border: 0; border-top: 1px solid #3a3a3a; margin: 28px 0; }
  a { color: #c5e384; }
</style>
</head>
<body><main>
${body}
</main></body>
</html>`;
}

router.get('/:document', (req, res) => {
  const meta = DOCUMENTS[req.params.document];
  if (!meta) return res.status(404).send('Документ не найден');

  if (cache.has(req.params.document)) {
    res.set('Content-Type', 'text/html; charset=utf-8');
    return res.send(cache.get(req.params.document));
  }

  try {
    const source = fs.readFileSync(path.join(LEGAL_DIR, meta.file), 'utf-8');
    const html = page(meta.title, renderMarkdown(source));
    cache.set(req.params.document, html);

    res.set('Content-Type', 'text/html; charset=utf-8');
    return res.send(html);
  } catch (err) {
    logger.error({ err, document: req.params.document }, 'Не удалось прочитать документ');
    return res.status(500).send('Документ временно недоступен');
  }
});

module.exports = router;