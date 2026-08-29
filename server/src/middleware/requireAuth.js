const {
  resolveAuthToken,
  extractBearerToken,
  touchAuthToken,
} = require('../infrastructure/authTokens');
const { describeDevice } = require('../utils/device');
const { t } = require('../infrastructure/i18n');

const SESSION_TOUCH_INTERVAL_MS = 5 * 60 * 1000;

function touchSession(req) {
  const now = Date.now();
  if (req.session.lastSeenAt && now - req.session.lastSeenAt < SESSION_TOUCH_INTERVAL_MS) return;

  req.session.lastSeenAt = now;
  if (!req.session.device) req.session.device = describeDevice(req);
  if (!req.session.createdAt) req.session.createdAt = now;
}

const requireAuth = async (req, res, next) => {
  try {
    if (req.session?.userId) {
      req.userId = req.session.userId;
      req.authVia = 'session';
      touchSession(req);
      return next();
    }

    const token = extractBearerToken(req);
    if (token) {
      const userId = await resolveAuthToken(token);
      if (userId) {
        req.userId = userId;
        req.authVia = 'token';
        req.authToken = token;
        touchAuthToken(token).catch(() => {});
        return next();
      }
    }

    return res.status(401).json({ error: t(req, 'unauthorized') });
  } catch (err) {
    next(err);
  }
};

module.exports = requireAuth;