const fs = require('fs');
const s = fs.readFileSync('server/src/controllers/authController.js','utf8');
const m = s.match(/`/g) || [];
console.log('backtick count:', m.length);
s.split('\n').forEach((l,i)=>{ const c=(l.match(/`/g)||[]).length; if(c%2===1) console.log('odd backticks at line',i+1, c, l.trim().slice(0,200)); });
