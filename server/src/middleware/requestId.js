const crypto = require('crypto');

function genId() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return crypto.randomBytes(16).toString('hex');
}

module.exports = function requestId(req, res, next) {
  try {
    const headerId = req.get('x-request-id') || req.get('X-Request-Id');
    const id = headerId || genId();
    req.id = id;
    // Ensure header is set on response
    if (!res.getHeader || typeof res.setHeader !== 'function') return next();
    res.setHeader('x-request-id', id);
    next();
  } catch (err) {
    // If anything goes wrong, continue without request id
    next();
  }
};
