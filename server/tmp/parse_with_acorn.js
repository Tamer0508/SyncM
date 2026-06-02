const fs = require('fs');
const acorn = require('acorn');
const code = fs.readFileSync('src/controllers/authController.js','utf8');
try {
  acorn.parse(code, { ecmaVersion: 2024, sourceType: 'module' });
  console.log('ACORN_PARSE_OK');
} catch (e) {
  console.error('Acorn error:', e.message);
  if (e.loc) console.error('Line', e.loc.line, 'Column', e.loc.column);
  process.exit(1);
}
