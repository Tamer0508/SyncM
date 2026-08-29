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

function assertValidLimitConfig(limit, windowSeconds) {
  if (!Number.isInteger(limit) || limit <= 0 || !Number.isInteger(windowSeconds) || windowSeconds <= 0) {
    throw new Error(
      `Rate limiter: limit and windowSeconds must be positive integers (got limit=${limit}, windowSeconds=${windowSeconds})`
    );
  }
}

let lastRateLimitErrorTime = 0;
const ERROR_LOG_THROTTLE_MS = 10000;

function logThrottled(level, obj, msg) {
  const now = Date.now();
  if (now - lastRateLimitErrorTime > ERROR_LOG_THROTTLE_MS) {
    logger[level](obj, msg);
    lastRateLimitErrorTime = now;
  }
}

async function rateLimit(key, limit, windowSeconds, { failOpen = true } = {}) {
  assertValidLimitConfig(limit, windowSeconds);

  const nowSeconds = () => Math.floor(Date.now() / 1000);
  const degradedResult = () => ({
    allowed: failOpen,
    remaining: failOpen ? limit : 0,
    reset: nowSeconds() + windowSeconds,
    degraded: true,
  });

  if (!redis.isRedisAvailable()) {
    logThrottled('warn', { key }, 'Redis unavailable, rate limiter operating in degraded mode');
    return degradedResult();
  }

  try {
    const [current, ttl] = await redis.redisClient.eval(rateLimitScript, 1, key, windowSeconds);

    const ttlVal = ttl < 0 ? windowSeconds : ttl;

    return {
      allowed: current <= limit,
      remaining: Math.max(0, limit - current),
      reset: nowSeconds() + ttlVal,
      degraded: false,
    };
  } catch (err) {
    logThrottled('error', { err, key }, 'Failed to evaluate rate limit script');
    return degradedResult();
  }
}

function rateLimitMiddleware(limit, windowSeconds, options = {}) {
  assertValidLimitConfig(limit, windowSeconds);
  const { keyGenerator = null, failOpen = true } = options;

  return function rateLimiter(req, res, next) {
    (async () => {
      let key;

      if (keyGenerator) {
        key = keyGenerator(req);
      } else {
        const userId = req.userId || req.session?.userId;

        const rawRouteKey = `${req.baseUrl || ''}${req.route?.path || req.path || ''}`;
        const routeKey = String(rawRouteKey).replace(/[^a-zA-Z0-9_\-/]/g, '_');

        if (userId) {
          key = `rate:user:${userId}:${req.method}:${routeKey}`;
        } else {
          const ip = req.ip || req.socket?.remoteAddress || 'unknown';
          const safeIp = String(ip).replace(/:/g, '_');
          key = `rate:ip:${safeIp}:${req.method}:${routeKey}`;
        }
      }

      const result = await rateLimit(key, limit, windowSeconds, { failOpen });

      res.setHeader('X-RateLimit-Limit', limit);
      res.setHeader('X-RateLimit-Remaining', result.remaining);
      res.setHeader('X-RateLimit-Reset', result.reset);

      if (!result.allowed) {
        const status = result.degraded ? 503 : 429;
        return res.status(status).json({
          error: result.degraded ? 'Rate limiting temporarily unavailable' : 'Too many requests',
          retryAfter: result.reset - Math.floor(Date.now() / 1000),
        });
      }

      next();
    })().catch((err) => {
      logger.error({ err }, 'Rate limiter middleware error');
      next();
    });
  };
}

module.exports = { rateLimit, rateLimitMiddleware };