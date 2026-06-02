const crypto = require('crypto');

function genId() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return crypto.randomBytes(16).toString('hex');
}

module.exports = function requestId(req, res, next) {
  const headerId = req.get('X-Request-Id') || req.get('x-request-id') || req.headers['x-request-id'] || req.headers['X-Request-Id'];
  const id = headerId || genId();
  req.id = id;

  if (typeof res.setHeader === 'function') {
    res.setHeader('X-Request-Id', id);
  }

  next();
};
