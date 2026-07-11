const Redis = require('ioredis');
const logger = require('./logger');

const REDIS_URL = process.env.REDIS_URL;

if (!REDIS_URL) {
  logger.warn('REDIS_URL is not configured. Redis caching will be disabled.');
}

let redisClient = null;
let isRedisReady = false;

if (REDIS_URL) {
  redisClient = new Redis(REDIS_URL, {
    maxRetriesPerRequest: null,
    retryStrategy(times) {
      const delay = Math.min(times * 50, 2000);
      logger.info({ attempt: times, delay }, `Redis reconnecting attempt ${times}, delay ${delay}ms`);
      return delay;
    },
    enableReadyCheck: true,
    reconnectOnError(err) {
      logger.error({ err }, 'Redis connection error');
      const targetErrors = ['READONLY', 'ETIMEDOUT', 'ECONNRESET'];
      return targetErrors.some(e => err.message.includes(e));
    }
  });

  redisClient.on('connect', () => logger.info('Redis client connected'));
  redisClient.on('ready', () => {
    isRedisReady = true;
    logger.info('Redis ready to accept commands');
  });
  redisClient.on('error', (err) => {
    logger.error({ err }, 'Redis error');
  });
  redisClient.on('close', () => {
    logger.warn('Redis connection closed');
    isRedisReady = false;
  });
  redisClient.on('end', () => {
    logger.warn('Redis connection ended');
    isRedisReady = false;
  });
}

const pendingFetches = new Map(); // fullKey -> Promise

function isRedisAvailable() {
  return redisClient && isRedisReady;
}

async function get(key) {
  if (!isRedisAvailable()) return null;
  try {
    const data = await redisClient.get(key);
    return data ? JSON.parse(data) : null;
  } catch (err) {
    logger.error({ err, key }, `Redis get error for key "${key}"`);
    return null;
  }
}

async function set(key, value, ttlSeconds) {
  if (!isRedisAvailable()) return false;
  try {
    const serialized = JSON.stringify(value);
    await redisClient.setex(key, ttlSeconds, serialized);
    return true;
  } catch (err) {
    logger.error({ err, key }, `Redis set error for key "${key}"`);
    return false;
  }
}

async function del(key) {
  if (!isRedisAvailable()) return false;
  try {
    await redisClient.del(key);
    return true;
  } catch (err) {
    logger.error({ err, key }, `Redis del error for key "${key}"`);
    return false;
  }
}

async function getWithTTL(key) {
  if (!isRedisAvailable()) return null;
  try {
    const pipeline = redisClient.pipeline();
    pipeline.get(key);
    pipeline.ttl(key);
    const results = await pipeline.exec();
    if (!results || results.length !== 2) return null;
    const value = results[0][1];
    const ttl = results[1][1];
    if (!value) return null;
    return { value: JSON.parse(value), ttl: ttl };
  } catch (err) {
    logger.error({ err, key }, 'Redis getWithTTL error');
    return null;
  }
}

async function acquireLock(lockKey, ttlSeconds = 5) {
  if (!isRedisAvailable()) return false;
  try {
    const result = await redisClient.set(lockKey, 'locked', 'NX', 'EX', ttlSeconds);
    return result === 'OK';
  } catch (err) {
    logger.error({ err, lockKey }, `Redis acquireLock error for ${lockKey}`);
    return false;
  }
}

async function releaseLock(lockKey) {
  if (!isRedisAvailable()) return false;
  try {
    await redisClient.del(lockKey);
    return true;
  } catch (err) {
    logger.error({ err, lockKey }, `Redis releaseLock error for ${lockKey}`);
    return false;
  }
}

async function deleteByPattern(pattern) {
  if (!isRedisAvailable()) return 0;
  let deletedCount = 0;
  let cursor = '0';
  try {
    do {
      const reply = await redisClient.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
      cursor = reply[0];
      const keys = reply[1];
      if (keys.length) {
        await redisClient.del(...keys);
        deletedCount += keys.length;
      }
    } while (cursor !== '0');
    logger.info({ pattern, deletedCount }, `Deleted ${deletedCount} keys matching pattern: ${pattern}`);
    return deletedCount;
  } catch (err) {
    logger.error({ err, pattern }, `Error deleting by pattern ${pattern}`);
    return 0;
  }
}

//  Cache versioning
const VERSION_KEY = 'cache:version';

async function getCacheVersion() {
  if (!isRedisAvailable()) return 0;
  try {
    const version = await redisClient.get(VERSION_KEY);
    return version ? parseInt(version, 10) : 0;
  } catch (err) {
    logger.error({ err }, 'Failed to get cache version');
    return 0;
  }
}

async function incrementVersion() {
  if (!isRedisAvailable()) return 0;
  try {
    const newVersion = await redisClient.incr(VERSION_KEY);
    logger.info({ newVersion }, 'Cache version incremented');
    return newVersion;
  } catch (err) {
    logger.error({ err }, 'Failed to increment cache version');
    return 0;
  }
}

function buildVersionedKey(version, key) {
  return `cache:v${version}:${key}`;
}

async function getVersioned(key) {
  if (!isRedisAvailable()) return null;
  const version = await getCacheVersion();
  const fullKey = buildVersionedKey(version, key);
  return get(fullKey);
}

async function setVersioned(key, value, ttlSeconds) {
  if (!isRedisAvailable()) return false;
  const version = await getCacheVersion();
  const fullKey = buildVersionedKey(version, key);
  return set(fullKey, value, ttlSeconds);
}

async function invalidateVersionedKey(key) {
  if (!isRedisAvailable()) return;
  const version = await getCacheVersion();
  const fullKey = buildVersionedKey(version, key);
  await del(fullKey);
}

async function getOrSet(key, ttlSeconds, fetchFn, { versioned = true } = {}) {
  if (!isRedisAvailable()) {
    return fetchFn();
  }

  let fullKey;
  if (versioned) {
    const version = await getCacheVersion();
    fullKey = buildVersionedKey(version, key);
  } else {
    fullKey = key;
  }

  // 1. Check cache
  const cached = await get(fullKey);
  if (cached !== null) {
    return cached;
  }

  // 2. In-flight deduplication
  if (pendingFetches.has(fullKey)) {
    logger.debug({ fullKey }, 'Awaiting in-flight fetch for key');
    return pendingFetches.get(fullKey);
  }

  // 3. Create new fetch promise
  const fetchPromise = (async () => {
    try {
      const result = await fetchFn();
      await set(fullKey, result, ttlSeconds).catch(err =>
        logger.error({ err, fullKey }, 'Failed to cache result in getOrSet')
      );
      return result;
    } catch (err) {
      logger.error({ err, fullKey }, 'Error in fetchFn for getOrSet');
      throw err;
    } finally {
      pendingFetches.delete(fullKey);
    }
  })();

  pendingFetches.set(fullKey, fetchPromise);
  return fetchPromise;
}

function clearPendingFetches() {
  pendingFetches.clear();
}

module.exports = {
  redisClient,
  get,
  set,
  del,
  getWithTTL,
  acquireLock,
  releaseLock,
  deleteByPattern,
  isRedisAvailable,
  getCacheVersion,
  incrementVersion,
  buildVersionedKey,
  getVersioned,
  setVersioned,
  invalidateVersionedKey,
  getOrSet,
  clearPendingFetches,
};