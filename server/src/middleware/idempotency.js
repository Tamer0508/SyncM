const crypto = require('crypto');
const { get, set, isRedisAvailable } = require('../infrastructure/redis');

const ID_TTL_SECONDS = 24 * 60 * 60; // 24 hours

function getUserIdFromReq(req) {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
}

module.exports = async function idempotencyMiddleware(req, res, next) {
  // Only proceed if Redis is available; otherwise simply continue
  if (!isRedisAvailable()) return next();

  try {
    let key = req.get('Idempotency-Key') || req.get('idempotency-key');
    const userId = getUserIdFromReq(req);

    if (!key) {
      const payload = {
        body: req.body || {},
        params: req.params || {},
        userId
      };
      key = crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
    }

    const storageKey = `idem:${key}`;

    const cached = await get(storageKey);
    if (cached) {
      // Return exactly the same status and body
      res.status(cached.status || 200).json(cached.body);
      return;
    }

    // Intercept response to capture body and status
    const originalJson = res.json.bind(res);
    const originalSend = res.send.bind(res);
    let responded = false;

    async function storeResponse(body) {
      if (responded) return;
      responded = true;
      const status = res.statusCode || 200;
      // Attempt to store; best-effort
      try {
        await set(storageKey, { status, body }, ID_TTL_SECONDS);
      } catch (e) {
        // swallow
        console.warn('Failed to store idempotency response:', e?.message || e);
      }
    }

    res.json = function (body) {
      // store asynchronously but don't await to avoid delaying response
      storeResponse(body).catch(() => {});
      return originalJson(body);
    };

    res.send = function (body) {
      // try to parse JSON bodies when possible
      let parsed = body;
      if (typeof body === 'string') {
        try { parsed = JSON.parse(body); } catch (e) { parsed = body; }
      }
      storeResponse(parsed).catch(() => {});
      return originalSend(body);
    };

    next();
  } catch (error) {
    // On any error, skip idempotency to avoid breaking requests
    console.error('Idempotency middleware error:', error?.message || error);
    next();
  }
};
