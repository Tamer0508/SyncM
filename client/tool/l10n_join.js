const fs = require('fs');

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Укажите файлы');
  process.exit(1);
}

const pair = /'([^'\\\n]*)'\s*\n\s*'([^'\\\n]*)'/;

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const crlf = raw.includes('\r\n');
  let text = raw.replace(/\r\n/g, '\n');

  let joined = 0;
  while (pair.test(text)) {
    text = text.replace(pair, (_, a, b) => `'${a}${b}'`);
    joined += 1;
    if (joined > 500) break;
  }

  fs.writeFileSync(file, crlf ? text.replace(/\n/g, '\r\n') : text);
  console.log(`${file}: склеено ${joined}`);
}
