const Redlock = require('redlock');
const logger = require('./logger');
const { redisClient, isRedisAvailable } = require('./redis');

let redlock = null;
if (isRedisAvailable()) {
  try {
    redlock = new Redlock([redisClient], {
      // Recommended sensible defaults
      driftFactor: 0.01,
      retryCount: 3,
      retryDelay: 200,
      retryJitter: 200,
    });

    redlock.on('clientError', (err) => {
      logger.error({ err }, 'Redlock client error');
    });
  } catch (err) {
    logger.error({ err }, 'Failed to initialize Redlock');
    redlock = null;
  }
} else {
  logger.warn('Redis is not available — distributed locks disabled');
}

async function withLock(resource, ttlMs, fn) {
  // resource is a logical name like 'friendship:123'
  const key = `locks:${resource}`;
  if (!redlock) {
    // fallback: execute without lock
    return await fn();
  }

  let lock = null;
  try {
    lock = await redlock.acquire([key], ttlMs);
  } catch (err) {
    // Could not acquire lock
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
      // best-effort release
      logger.warn({ err: releaseErr }, 'Failed to release lock');
    }
  }
}

module.exports = { withLock };
