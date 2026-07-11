const redis = require('./redis');
const logger = require('./logger');

const rateLimitScript = `
  local current = redis.call('INCR', KEYS[1])
  if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  local ttl = redis.call('TTL', KEYS[1])
  return {current, ttl}
`;

async function rateLimit(key, limit, windowSeconds) {
  if (!redis.isRedisAvailable()) {
    logger.warn('Rate limiter skipped: Redis unavailable');
    return { allowed: true, remaining: limit, reset: windowSeconds };
  }

  try {
    const [current, ttl] = await redis.redisClient.eval(
      rateLimitScript,
      1,
      key,
      windowSeconds
    );
    const allowed = current <= limit;
    const remaining = allowed ? limit - current : 0;
    const reset = ttl > 0
      ? Math.floor(Date.now() / 1000) + ttl
      : Math.floor(Date.now() / 1000) + windowSeconds;

    return { allowed, remaining, reset };
  } catch (err) {
    logger.error({ err }, 'Rate limiter error');
    return { allowed: true, remaining: limit, reset: windowSeconds };
  }
}

function rateLimitMiddleware(limit, windowSeconds, keyGenerator = null) {
  return async (req, res, next) => {
    let key;
    if (keyGenerator) {
      key = keyGenerator(req);
    } else {
      const userId = req.session?.userId;
      if (userId) {
        key = `rate:user:${userId}:${req.path}`;
      } else {
        const ip = req.ip || req.connection?.remoteAddress || 'unknown';
        key = `rate:ip:${ip}:${req.path}`;
      }
    }

    const result = await rateLimit(key, limit, windowSeconds);

    res.setHeader('X-RateLimit-Limit', limit);
    res.setHeader('X-RateLimit-Remaining', result.remaining);
    res.setHeader('X-RateLimit-Reset', result.reset);

    if (!result.allowed) {
      return res.status(429).json({
        error: 'Too many requests',
        retryAfter: result.reset - Math.floor(Date.now() / 1000)
      });
    }
    next();
  };
}

module.exports = { rateLimit, rateLimitMiddleware };