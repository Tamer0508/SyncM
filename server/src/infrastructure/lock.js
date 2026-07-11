const { default: Redlock } = require('redlock');
const logger = require('./logger');
const { redisClient, isRedisAvailable } = require('./redis');

let redlock = null;
let initAttempted = false;

function getRedlock() {
  if (redlock) return redlock;
  if (!isRedisAvailable()) {
    logger.warn('Redis not available, cannot create Redlock instance');
    return null;
  }
  try {
    redlock = new Redlock([redisClient], {
      driftFactor: 0.01,
      retryCount: 3,
      retryDelay: 200,
      retryJitter: 200,
    });

    redlock.on('clientError', (err) => {
      logger.error({ err }, 'Redlock client error');
    });

    logger.info('Redlock initialized successfully');
    return redlock;
  } catch (err) {
    logger.error({ err }, 'Failed to initialize Redlock');
    return null;
  }
}

async function withLock(resource, ttlMs, fn) {
  const key = `locks:${resource}`;
  const lockManager = getRedlock();

  if (!lockManager) {
    logger.warn({ key }, 'Redlock unavailable, executing without distributed lock');
    return await fn();
  }

  let lock = null;
  try {
    lock = await lockManager.acquire([key], ttlMs);
  } catch (err) {
    logger.error({ err, key }, 'Failed to acquire lock');
    const e = new Error('Could not acquire lock');
    e.cause = err;
    throw e;
  }

  try {
    const result = await fn();
    return result;
  } finally {
    try {
      if (lock) await lock.release();
    } catch (releaseErr) {
      logger.warn({ err: releaseErr, key }, 'Failed to release lock');
    }
  }
}

module.exports = { withLock, getRedlock };