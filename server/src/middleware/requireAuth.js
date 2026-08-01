const { resolveAuthToken, extractBearerToken } = require('../infrastructure/authTokens');

const requireAuth = async (req, res, next) => {
  try {
    if (req.session?.userId) {
      req.userId = req.session.userId;
      req.authVia = 'session';
      return next();
    }

    const token = extractBearerToken(req);
    if (token) {
      const userId = await resolveAuthToken(token);
      if (userId) {
        req.userId = userId;
        req.authVia = 'token';
        req.authToken = token; // нужен logout'у, чтобы отозвать именно его
        return next();
      }
    }

    return res.status(401).json({ error: 'Не авторизован' });
  } catch (err) {
    next(err);
  }
};

module.exports = requireAuth;