const { default: Redlock } = require('redlock');
const logger = require('./logger');
const { redisClient, isRedisAvailable } = require('./redis');

let redlock = null;
let initializationFailed = false;

function getRedlock() {
  if (redlock) return redlock;
  if (initializationFailed) return null;

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
      automaticExtensionThreshold: 500, // ms до истечения для продления
    });

    redlock.on('error', (err) => {
      logger.error({ err }, 'Redlock error');
    });

    logger.info('Redlock initialized successfully');
    return redlock;
  } catch (err) {
    initializationFailed = true;
    logger.error({ err }, 'Failed to initialize Redlock');
    return null;
  }
}

async function withLock(resource, ttlMs, fn, { failOpen = false } = {}) {
  const key = `locks:${resource}`;
  const lockManager = getRedlock();

  if (!lockManager) {
    if (failOpen) {
      logger.warn({ key }, 'Redlock unavailable, executing without distributed lock (failOpen)');
      return fn();
    }
    throw new Error(`Redlock unavailable, refusing to run "${resource}" without a lock`);
  }

  try {
    return await lockManager.using([key], ttlMs, async (signal) => {
      let onAbort;

      const abortPromise = new Promise((_, reject) => {
        if (signal.aborted) {
          return reject(signal.error || new Error('Lock was lost during execution'));
        }
        onAbort = () => reject(signal.error || new Error('Lock was lost during execution'));
        signal.addEventListener('abort', onAbort, { once: true });
      });

      try {
        return await Promise.race([fn(signal), abortPromise]);
      } finally {
        if (onAbort) signal.removeEventListener('abort', onAbort);
      }
    });
  } catch (err) {
    logger.error({ err, key }, 'Failed to execute function under lock');
    throw new Error(`Could not acquire or hold lock for "${resource}"`, { cause: err });
  }
}

module.exports = {
  withLock,
  getRedlock,
};