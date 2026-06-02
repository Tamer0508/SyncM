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

module.exports = {
  redisClient,
  get,
  set,
  del,
  getWithTTL,
  acquireLock,
  releaseLock,
  isRedisAvailable,
  deleteByPattern
};