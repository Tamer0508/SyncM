// Склеивает соседние строковые литералы в один.
//
// В Dart два литерала подряд — это конкатенация: длинный текст разбивают по
// строкам, чтобы влезал в ширину файла. Для переноса в ARB такой текст должен
// быть цельным, иначе в словарь попадут обрывки фраз, которые невозможно
// перевести.
//
//   node tool/l10n_join.js lib/screens/foo.dart

const fs = require('fs');

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Укажите файлы');
  process.exit(1);
}

// Между литералами только пробелы и переводы строк — значит, это склейка, а не
// два разных аргумента (там был бы хотя бы запятая).
const pair = /'([^'\\\n]*)'\s*\n\s*'([^'\\\n]*)'/;

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const crlf = raw.includes('\r\n');
  let text = raw.replace(/\r\n/g, '\n');

  let joined = 0;
  while (pair.test(text)) {
    text = text.replace(pair, (_, a, b) => `'${a}${b}'`);
    joined += 1;
    if (joined > 500) break; // страховка от зацикливания
  }

  fs.writeFileSync(file, crlf ? text.replace(/\n/g, '\r\n') : text);
  console.log(`${file}: склеено ${joined}`);
}
