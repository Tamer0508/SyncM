const crypto = require('crypto');
const { get, set, isRedisAvailable } = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');

const ID_TTL_SECONDS = 30; 

const MUTATING_METHODS = ['POST', 'PUT', 'PATCH', 'DELETE'];

function getUserIdFromReq(req) {
  if (req.user?.id) return req.user.id;
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return '';
}

/**
 * Генерирует детерминированный ключ идемпотентности,
 * если клиент не передал явный Idempotency-Key.
 */
function generateDefaultKey(req) {
  const userId = getUserIdFromReq(req);
  const payload = JSON.stringify({
    method: req.method,
    path: req.originalUrl || req.url,
    body: req.body,
    userId,
  });
  return crypto.createHash('sha256').update(payload).digest('hex');
}

module.exports = function idempotencyMiddleware(req, res, next) {
  // Применяем только к мутирующим методам
  if (!MUTATING_METHODS.includes(req.method)) return next();

  // Если Redis недоступен – пропускаем
  if (!isRedisAvailable()) {
    logger.warn('Redis unavailable, skipping idempotency check');
    return next();
  }

  (async () => {
    try {
      // 1. Определяем ключ
      let idempotencyKey = req.get('Idempotency-Key') || req.get('idempotency-key');
      if (!idempotencyKey) {
        idempotencyKey = generateDefaultKey(req);
        logger.debug({ idempotencyKey }, 'Generated default idempotency key');
      }

      const storageKey = `idem:${idempotencyKey}`;

      // 2. Проверяем, нет ли сохранённого ответа
      const cached = await get(storageKey);
      if (cached && cached.status != null) {
        logger.info({ storageKey }, 'Returning cached idempotent response');
        if (cached.headers?.['content-type']) {
          res.setHeader('Content-Type', cached.headers['content-type']);
        }
        return res.status(cached.status).json(cached.body);
      }

      // 3. Перехватываем отправку ответа, чтобы сохранить его
      const originalJson = res.json.bind(res);
      const originalSend = res.send.bind(res);
      let stored = false;

      const storeResponse = async (body) => {
        if (stored) return;
        stored = true;
        const status = res.statusCode || 200;
        const headers = {};
        const contentType = typeof res.getHeader === 'function' ? res.getHeader('content-type') : null;
        if (contentType) headers['content-type'] = contentType;
        await set(storageKey, { status, body, headers }, ID_TTL_SECONDS).catch((err) =>
          logger.error({ err, storageKey }, 'Failed to store idempotent response')
        );
        logger.debug({ storageKey }, 'Stored idempotent response');
      };

      res.json = function (body) {
        storeResponse(body);
        return originalJson(body);
      };

      res.send = function (body) {
        let parsed = body;
        if (typeof body === 'string') {
          try {
            parsed = JSON.parse(body);
          } catch (e) {
            // оставляем как есть
          }
        }
        storeResponse(parsed);
        return originalSend(body);
      };

      next();
    } catch (error) {
      logger.error({ err: error }, 'Idempotency middleware error, passing through');
      next();
    }
  })();
};