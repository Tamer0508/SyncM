const { PrismaClient } = require('@prisma/client');

// В продакшене логируем только ошибки и предупреждения.
// В режиме разработки можно включить 'query' для отладки.
const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'production' 
    ? ['error', 'warn'] 
    : ['error', 'warn'],
});

module.exports = prisma;
