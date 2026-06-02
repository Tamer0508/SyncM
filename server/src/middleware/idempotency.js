const crypto = require('crypto');
const { get, set, isRedisAvailable } = require('../infrastructure/redis');

const ID_TTL_SECONDS = 24 * 60 * 60; // 24 hours

function getUserIdFromReq(req) {
  if (req.user?.id) return req.user.id;
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return '';
}

module.exports = async function idempotencyMiddleware(req, res, next) {
  if (!isRedisAvailable()) return next();

  try {
    let key = req.get('Idempotency-Key') || req.get('idempotency-key');
    if (!key) {
      const userId = getUserIdFromReq(req);
      key = crypto.createHash('sha256').update(JSON.stringify(req.body || {}) + userId).digest('hex');
    }

    const storageKey = `idem:${key}`;
    const cached = await get(storageKey);
    if (cached && cached.status != null) {
      if (cached.headers?.['content-type']) {
        res.setHeader('Content-Type', cached.headers['content-type']);
      }
      return res.status(cached.status).json(cached.body);
    }

    const originalJson = res.json.bind(res);
    const originalSend = res.send.bind(res);
    let stored = false;

    async function storeResponse(body) {
      if (stored) return;
      stored = true;
      const status = res.statusCode || 200;
      const headers = {};
      const contentType = typeof res.getHeader === 'function' ? res.getHeader('content-type') : null;
      if (contentType) headers['content-type'] = contentType;
      await set(storageKey, { status, body, headers }, ID_TTL_SECONDS).catch(() => {});
    }

    res.json = function (body) {
      storeResponse(body).catch(() => {});
      return originalJson(body);
    };

    res.send = function (body) {
      let parsed = body;
      if (typeof body === 'string') {
        try { parsed = JSON.parse(body); } catch (e) { parsed = body; }
      }
      storeResponse(parsed).catch(() => {});
      return originalSend(body);
    };

    next();
  } catch (error) {
    next();
  }
};
