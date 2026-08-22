const crypto = require('crypto');
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
    maxRetriesPerRequest: 3,
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

const pendingFetches = new Map(); 

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
  if (!isRedisAvailable()) return null;
  const token = crypto.randomUUID();
  try {
    const result = await redisClient.set(lockKey, token, 'NX', 'EX', ttlSeconds);
    return result === 'OK' ? token : null;
  } catch (err) {
    logger.error({ err, lockKey }, `Redis acquireLock error for ${lockKey}`);
    return null;
  }
}

const RELEASE_LOCK_SCRIPT = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end`;

async function releaseLock(lockKey, token) {
  if (!isRedisAvailable()) return false;
  try {
    const result = await redisClient.eval(RELEASE_LOCK_SCRIPT, 1, lockKey, token);
    return result === 1;
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


function versionKeyFor(namespace) {
  return `cache:ver:${namespace}`;
}

async function getCacheVersion(namespace) {
  if (!isRedisAvailable()) return 0;
  try {
    const version = await redisClient.get(versionKeyFor(namespace));
    return version ? parseInt(version, 10) : 0;
  } catch (err) {
    logger.error({ err, namespace }, `Failed to get cache version for namespace "${namespace}"`);
    return 0;
  }
}

async function incrementVersion(namespace) {
  if (!isRedisAvailable()) return 0;
  try {
    const newVersion = await redisClient.incr(versionKeyFor(namespace));
    logger.info({ namespace, newVersion }, `Cache version incremented for namespace "${namespace}"`);
    return newVersion;
  } catch (err) {
    logger.error({ err, namespace }, `Failed to increment cache version for namespace "${namespace}"`);
    return 0;
  }
}

function buildVersionedKey(namespace, version, key) {
  return `cache:${namespace}:v${version}:${key}`;
}

async function getVersioned(namespace, key) {
  if (!isRedisAvailable()) return null;
  const version = await getCacheVersion(namespace);
  return get(buildVersionedKey(namespace, version, key));
}

async function setVersioned(namespace, key, value, ttlSeconds) {
  if (!isRedisAvailable()) return false;
  const version = await getCacheVersion(namespace);
  return set(buildVersionedKey(namespace, version, key), value, ttlSeconds);
}

async function invalidateVersionedKey(namespace, key) {
  if (!isRedisAvailable()) return;
  const version = await getCacheVersion(namespace);
  await del(buildVersionedKey(namespace, version, key));
}

const READ_VERSIONED_SCRIPT = `
local ver = redis.call('GET', KEYS[1])
if not ver then ver = '0' end
local val = redis.call('GET', ARGV[1] .. ver .. ARGV[2])
if not val then return {ver} end
return {ver, val}
`;

function parseVersionedReply(namespace, key, reply) {
  const version = parseInt(reply?.[0], 10) || 0;
  const fullKey = buildVersionedKey(namespace, version, key);
  const raw = reply?.[1];

  if (!raw) return { fullKey, value: null };

  try {
    return { fullKey, value: JSON.parse(raw) };
  } catch (err) {
    logger.warn({ err, fullKey }, 'Cached value is not valid JSON, treating as miss');
    return { fullKey, value: null };
  }
}

async function readVersioned(namespace, key) {
  try {
    const reply = await redisClient.eval(
      READ_VERSIONED_SCRIPT,
      1,
      versionKeyFor(namespace),
      `cache:${namespace}:v`,
      `:${key}`
    );

    return parseVersionedReply(namespace, key, reply);
  } catch (err) {
    logger.warn({ err, namespace }, 'Versioned read script failed, falling back to plain GETs');
    const version = await getCacheVersion(namespace);
    const fullKey = buildVersionedKey(namespace, version, key);
    return { fullKey, value: await get(fullKey) };
  }
}

async function getOrSet(namespace, key, ttlSeconds, fetchFn, { versioned = true, lockTtlSeconds = 10 } = {}) {
  if (!isRedisAvailable()) {
    return fetchFn();
  }

  let fullKey;
  let cached;

  if (versioned) {
    ({ fullKey, value: cached } = await readVersioned(namespace, key));
  } else {
    fullKey = `cache:${namespace}:${key}`;
    cached = await get(fullKey);
  }

  if (cached !== null) {
    return cached;
  }

  if (pendingFetches.has(fullKey)) {
    logger.debug({ fullKey }, 'Awaiting in-process in-flight fetch for key');
    return pendingFetches.get(fullKey);
  }

  const fetchPromise = (async () => {
    try {
      const lockKey = `lock:${fullKey}`;
      const token = await acquireLock(lockKey, lockTtlSeconds);

      if (!token) {
        await new Promise(resolve => setTimeout(resolve, 100));
        const retryCached = await get(fullKey);
        if (retryCached !== null) return retryCached;
        return fetchFn();
      }

      try {
        const result = await fetchFn();
        await set(fullKey, result, ttlSeconds);
        return result;
      } finally {
        await releaseLock(lockKey, token);
      }
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
  parseVersionedReply,
  READ_VERSIONED_SCRIPT,
};