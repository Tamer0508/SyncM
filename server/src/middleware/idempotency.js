const crypto = require('crypto');
const { get, set, acquireLock, releaseLock, isRedisAvailable } = require('../infrastructure/redis');
const { resolveUserId } = require('./requireAuth');
const logger = require('../infrastructure/logger');

const DEFAULT_RESULT_TTL_SECONDS = 30;
const DEFAULT_LOCK_TTL_SECONDS = 20;
const MUTATING_METHODS = ['POST', 'PUT', 'PATCH', 'DELETE'];

const REPLAYED_HEADERS = ['content-type', 'content-disposition'];

function stableStringify(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`;
}

function requestFingerprint(req) {
  const payload = stableStringify({
    method: req.method,
    path: req.originalUrl || req.url,
    body: req.body,
    userId: resolveUserId(req) || '',
  });
  return crypto.createHash('sha256').update(payload).digest('hex');
}

module.exports = function idempotencyMiddleware(options = {}) {
  const {
    resultTtlSeconds = DEFAULT_RESULT_TTL_SECONDS,
    lockTtlSeconds = DEFAULT_LOCK_TTL_SECONDS,
  } = options;

  return function idempotency(req, res, next) {
    if (!MUTATING_METHODS.includes(req.method)) return next();

    if (!isRedisAvailable()) {
      (req.log || logger).warn('Redis unavailable, skipping idempotency');
      return next();
    }

    (async () => {
      let lockToken = null;
      let lockKey = null;
      const log = req.log || logger;

      try {
        const fingerprint = requestFingerprint(req);

        let idempotencyKey = req.headers['idempotency-key'];
        if (!idempotencyKey || typeof idempotencyKey !== 'string') {
          idempotencyKey = fingerprint;
        }

        const storageKey = `idem:${idempotencyKey}:${fingerprint}`;
        lockKey = `idem-lock:${idempotencyKey}:${fingerprint}`;

        const replay = (cached) => {
          log.info({ storageKey }, 'Returning cached idempotent response');

          if (cached.headers) {
            for (const [key, value] of Object.entries(cached.headers)) {
              res.setHeader(key, value);
            }
          }

          if (cached.kind === 'send') {
            return res.status(cached.status).send(cached.body);
          }
          return res.status(cached.status).json(cached.body);
        };

        const cached = await get(storageKey).catch((err) => {
          log.error({ err, storageKey }, 'Redis get error');
          return null;
        });

        if (cached && cached.status != null) return replay(cached);

        const token = await acquireLock(lockKey, lockTtlSeconds).catch((err) => {
          log.error({ err, lockKey }, 'Redis lock error');
          return null;
        });

        if (!token) {
          await new Promise((resolve) => setTimeout(resolve, 250));
          const recheck = await get(storageKey).catch(() => null);
          if (recheck && recheck.status != null) return replay(recheck);

          return res.status(409).json({
            error: 'Conflict',
            message: 'A request with this idempotency key is already being processed',
          });
        }

        lockToken = token;

        const originalJson = res.json.bind(res);
        const originalSend = res.send.bind(res);
        let storePromise = null;

        const storeResponse = (body, kind) => {
          if (storePromise) return storePromise;

          storePromise = (async () => {
            if (Buffer.isBuffer(body)) {
              log.debug({ storageKey }, 'Skipping idempotency cache for binary/Buffer');
              return;
            }

            try {
              const status = res.statusCode || 200;
              if (status >= 500) {
                log.debug({ storageKey, status }, 'Skipping cache for server error');
                return;
              }

              const headers = {};
              if (typeof res.getHeaders === 'function') {
                const currentHeaders = res.getHeaders();
                for (const key of REPLAYED_HEADERS) {
                  if (currentHeaders[key]) headers[key] = currentHeaders[key];
                }
              }

              await set(storageKey, { status, body, headers, kind }, resultTtlSeconds);
            } catch (err) {
              log.error({ err, storageKey }, 'Failed to store idempotent response');
            }
          })();
          return storePromise;
        };

        res.json = function (body) {
          storeResponse(body, 'json');
          return originalJson(body);
        };

        res.send = function (body) {
          storeResponse(body, 'send');
          return originalSend(body);
        };

        let lockReleased = false;
        const releaseIdemLock = async () => {
          if (lockReleased) return;
          lockReleased = true;

          if (storePromise) await storePromise.catch(() => {});

          await releaseLock(lockKey, token).catch((err) =>
            log.error({ err, lockKey }, 'Failed to release idempotency lock')
          );
        };

        res.once('finish', releaseIdemLock);
        res.once('close', releaseIdemLock);
        res.once('error', releaseIdemLock);

        next();
      } catch (error) {
        log.error({ err: error }, 'Idempotency middleware unexpected error');
        if (lockToken && lockKey) {
          await releaseLock(lockKey, lockToken).catch(() => {});
        }
        next();
      }
    })();
  };
};