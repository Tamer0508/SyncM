const fs = require('fs');

const file = process.argv[2];
if (!file) {
  console.error('Укажите файл: node tool/l10n_extract.js lib/screens/foo.dart');
  process.exit(1);
}

const source = fs.readFileSync(file, 'utf8');

const found = new Map();
const re = /'([^'\\\n]*[А-Яа-яЁё][^'\\\n]*)'/g;

let match;
while ((match = re.exec(source)) !== null) {
  const text = match[1];
  found.set(text, (found.get(text) || 0) + 1);
}

const entries = [...found.entries()].sort((a, b) => b[1] - a[1]);

console.log(JSON.stringify(
  {
    file,
    strings: entries.map(([text, count]) => ({
      count,
      interpolated: text.includes('$'),
      ru: text,
    })),
  },
  null,
  2
));
