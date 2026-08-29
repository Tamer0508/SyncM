const fs = require('fs');
const path = require('path');

const CONST_CODES = ['const_eval_method_invocation', 'invalid_constant', 'const_initialized_with_non_constant_value'];

let input = '';
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  const byFile = new Map();

  for (const line of input.split('\n')) {
    if (!CONST_CODES.some((code) => line.includes(code))) continue;

    const match = line.match(/- (lib[\\/][^\s:]+\.dart):(\d+):\d+/);
    if (!match) continue;

    const file = match[1].replace(/\\/g, '/');
    if (!byFile.has(file)) byFile.set(file, new Set());
    byFile.get(file).add(Number(match[2]));
  }

  let total = 0;

  for (const [file, lines] of byFile) {
    const full = path.resolve(file);
    if (!fs.existsSync(full)) {
      console.error(`нет файла: ${file}`);
      continue;
    }

    const raw = fs.readFileSync(full, 'utf8');
    const crlf = raw.includes('\r\n');
    const text = raw.replace(/\r\n/g, '\n').split('\n');

    for (const lineNumber of [...lines].sort((a, b) => a - b)) {
      const index = lineNumber - 1;

      for (let i = index; i >= 0 && i > index - 25; i -= 1) {
        const before = text[i];
        const after = before
          .replace(/\bconst\s+(?=[A-Z_[{])/, '')
          .replace(/:\s*const\s+(?=[A-Z_[{])/, ': ');

        if (after !== before) {
          text[i] = after;
          total += 1;
          break;
        }
      }
    }

    fs.writeFileSync(full, crlf ? text.join('\n').replace(/\n/g, '\r\n') : text.join('\n'));
  }

  console.log(`Убрано const: ${total}`);
});
