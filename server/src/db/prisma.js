const { PrismaClient } = require('@prisma/client');
const logger = require('../infrastructure/logger');

const isProd = process.env.NODE_ENV === 'production';

const logDefinition = [
  { emit: 'event', level: 'error' },
  { emit: 'event', level: 'warn' },
  ...(isProd ? [] : [{ emit: 'event', level: 'query' }]),
];

function createPrismaClient() {
  const client = new PrismaClient({ log: logDefinition });

  client.$on('error', (e) => logger.error({ target: e.target }, e.message));
  client.$on('warn', (e) => logger.warn({ target: e.target }, e.message));

  if (!isProd) {
    client.$on('query', (e) => {
      logger.debug({ durationMs: e.duration, params: e.params }, e.query);
    });
  }

  return client;
}

const globalForPrisma = globalThis;

const prisma = isProd
  ? createPrismaClient()
  : (globalForPrisma.__syncmPrisma ?? (globalForPrisma.__syncmPrisma = createPrismaClient()));

module.exports = prisma;