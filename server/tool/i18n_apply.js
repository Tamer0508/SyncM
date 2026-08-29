const fs = require('fs');
const path = require('path');

const { MESSAGES } = require('../src/infrastructure/i18n');

const BY_TEXT = new Map(
  Object.entries(MESSAGES).map(([key, value]) => [value.ru, key])
);

const FILES = [
  'src/controllers/authController.js',
  'src/controllers/friendsController.js',
  'src/controllers/playlistController.js',
  'src/controllers/sessionController.js',
  'src/routes/spotify.js',
  'src/index.js',
];

const root = path.resolve(__dirname, '..');
let total = 0;

for (const file of FILES) {
  const full = path.join(root, file);
  const raw = fs.readFileSync(full, 'utf8');
  const crlf = raw.includes('\r\n');
  let text = raw.replace(/\r\n/g, '\n');

  for (const [russian, key] of BY_TEXT) {
    const literal = `error: '${russian}'`;
    if (!text.includes(literal)) continue;

    const parts = text.split(literal);
    total += parts.length - 1;
    text = parts.join(`error: t(req, '${key}')`);
  }

  if (raw !== text && !text.includes("require('../infrastructure/i18n')") &&
      !text.includes("require('./infrastructure/i18n')")) {
    const depth = file.startsWith('src/routes') || file.startsWith('src/controllers')
      ? '../infrastructure/i18n'
      : './infrastructure/i18n';
    const firstRequire = text.split('\n').find((line) => line.startsWith('const '));
    text = text.replace(firstRequire, `const { t } = require('${depth}');\n${firstRequire}`);
  }

  fs.writeFileSync(full, crlf ? text.replace(/\n/g, '\r\n') : text);
}

console.log(`Заменено сообщений: ${total}`);
