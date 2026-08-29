const fs = require('fs');
const path = 'server/src/controllers/authController.js';
const s = fs.readFileSync(path, 'utf8');
const lines = s.split('\n');
for (let i = 0; i < lines.length; i++) {
  const prefix = lines.slice(0, i+1).join('\n');
  try {
    new Function(prefix);
  } catch (e) {
    console.error('Syntax error near line', i+1, e.toString());
    const start = Math.max(0, i-5);
    const end = Math.min(lines.length, i+5);
    for (let j = start; j < end; j++) {
      console.error((j+1).toString().padStart(4,' ')+': '+lines[j]);
    }
    process.exit(1);
  }
}
console.log('No syntax errors detected by progressive parse.');
