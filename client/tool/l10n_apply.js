const fs = require('fs');
const path = require('path');

const mapPath = process.argv[2];
if (!mapPath) {
  console.error('Укажите карту: node tool/l10n_apply.js tool/l10n_map/foo.json');
  process.exit(1);
}

const root = path.resolve(__dirname, '..');
const map = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
const accessor = map.accessor || 'L.of(context)';

map.strings = map.strings.map((item) =>
  Array.isArray(item) ? { key: item[0], ru: item[1], en: item[2] } : item
);

const targets = Array.isArray(map.file) ? map.file : [map.file];

for (const [locale, field] of [['ru', 'ru'], ['en', 'en']]) {
  const arbPath = path.join(root, 'lib', 'l10n', `app_${locale}.arb`);
  const arb = JSON.parse(fs.readFileSync(arbPath, 'utf8'));

  for (const item of map.strings) {
    if (!item.key) continue;
    if (arb[item.key] !== undefined && arb[item.key] !== item[field]) {
      throw new Error(
        `Ключ ${item.key} уже занят другим текстом (${locale}): «${arb[item.key]}»`
      );
    }
    arb[item.key] = item[field];
  }

  const sorted = Object.fromEntries(
    Object.entries(arb).sort(([a], [b]) => (a.startsWith('@') ? -1 : a.localeCompare(b)))
  );

  fs.writeFileSync(arbPath, `${JSON.stringify(sorted, null, 2)}\n`);
}

let replaced = 0;
let untouched = [];

for (const target of targets) {
  const filePath = path.join(root, target);
  const raw = fs.readFileSync(filePath, 'utf8');
  const crlf = raw.includes('\r\n');
  let text = raw.replace(/\r\n/g, '\n');

  for (const item of map.strings) {
    if (!item.key || item.manual) continue;

    const literal = `'${item.ru}'`;
    if (!text.includes(literal)) continue;

    const call = `${item.accessor || accessor}.${item.key}`;
    const parts = text.split(literal);
    replaced += parts.length - 1;
    text = parts.join(call);
  }

  fs.writeFileSync(filePath, crlf ? text.replace(/\n/g, '\r\n') : text);
}

for (const item of map.strings) {
  if (!item.key) untouched.push(item.ru);
}

console.log(`Заменено вхождений: ${replaced}`);
if (untouched.length) {
  console.log(`Без ключа осталось: ${untouched.length}`);
}
