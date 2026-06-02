const Redis = require('ioredis');

const REDIS_URL = process.env.REDIS_URL;

if (!REDIS_URL) {
  console.warn(' REDIS_URL не задан в .env. Кэширование будет отключено (fallback).');
}

let redisClient = null;
let isRedisReady = false;

if (REDIS_URL) {
  redisClient = new Redis(REDIS_URL, {
    maxRetriesPerRequest: 3,
    retryStrategy(times) {
      const delay = Math.min(times * 50, 2000);
      console.log(` Redis reconnecting attempt ${times}, delay ${delay}ms`);
      return delay;
    },
    enableReadyCheck: true,
    reconnectOnError(err) {
      console.error('Redis connection error:', err.message);
      const targetErrors = ['READONLY', 'ETIMEDOUT', 'ECONNRESET'];
      return targetErrors.some(e => err.message.includes(e));
    }
  });

    redisClient.on('connect', () => console.log(' Redis client connected'));
    redisClient.on('ready', () => {
        isRedisReady = true;
        console.log(' Redis ready to accept commands');
    });
    redisClient.on('error', (err) => {
        // Просто логируем, но не меняем флаг готовности
        console.error(' Redis error:', err.message);
    });
    redisClient.on('close', () => {
        console.warn(' Redis connection closed');
        isRedisReady = false;
    });
    redisClient.on('end', () => {
        console.warn(' Redis connection ended');
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
    console.error(`Redis get error for key "${key}":`, err.message);
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
    console.error(`Redis set error for key "${key}":`, err.message);
    return false;
  }
}

async function del(key) {
  if (!isRedisAvailable()) return false;
  try {
    await redisClient.del(key);
    return true;
  } catch (err) {
    console.error(`Redis del error for key "${key}":`, err.message);
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
    console.error(`Redis getWithTTL error:`, err.message);
    return null;
  }
}

async function acquireLock(lockKey, ttlSeconds = 5) {
  if (!isRedisAvailable()) return false;
  try {
    const result = await redisClient.set(lockKey, 'locked', 'NX', 'EX', ttlSeconds);
    return result === 'OK';
  } catch (err) {
    console.error(`Redis acquireLock error for ${lockKey}:`, err.message);
    return false;
  }
}

async function releaseLock(lockKey) {
  if (!isRedisAvailable()) return false;
  try {
    await redisClient.del(lockKey);
    return true;
  } catch (err) {
    console.error(`Redis releaseLock error for ${lockKey}:`, err.message);
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
    console.log(` Deleted ${deletedCount} keys matching pattern: ${pattern}`);
    return deletedCount;
  } catch (err) {
    console.error(`Error deleting by pattern ${pattern}:`, err.message);
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