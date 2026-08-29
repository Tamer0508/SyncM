const express = require('express');
const router = express.Router();
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const idempotency = require('../middleware/idempotency')();
const requireAuth = require('../middleware/requireAuth');
const {
  login,
  callback,
  getMe,
  logout,
  googleAuth,
  getSettings,
  updateSettings,
  updateProfile,
  googleWebLogin,
  googleWebCallback,
  checkPendingAuth,
  uploadAvatar,
  deleteAccount,

  getPlayHistory,

  clearPlayHistory,

  createSpotifyLinkIntent,

  exportUserData,

  getDevices,

  revokeDevice,

  logoutEverywhere,
} = require('../controllers/authController');

const authLimit = (limit, windowSeconds) =>
  rateLimitMiddleware(limit, windowSeconds, { failOpen: false });

router.get('/login',           authLimit(10, 60), login);
router.get('/callback',        authLimit(10, 60), callback);
router.post('/google',         authLimit(10, 60), googleAuth);
router.get('/google-web',      authLimit(10, 60), googleWebLogin);
router.get('/google-callback', authLimit(10, 60), googleWebCallback);
router.get('/check-pending',   authLimit(20, 60), checkPendingAuth);

router.post('/spotify/link-intent', requireAuth, rateLimitMiddleware(10, 60), createSpotifyLinkIntent);

router.get('/me',          requireAuth, rateLimitMiddleware(15, 60), getMe);
router.get('/logout',      requireAuth, rateLimitMiddleware(10, 60), logout);
router.post('/avatar',     requireAuth, rateLimitMiddleware(10, 60), uploadAvatar);
router.get('/settings',    requireAuth, rateLimitMiddleware(15, 60), getSettings);
router.patch('/settings',  requireAuth, rateLimitMiddleware(10, 60), idempotency, updateSettings);
router.patch('/profile',   requireAuth, rateLimitMiddleware(10, 60), idempotency, updateProfile);

router.get('/devices',              requireAuth, rateLimitMiddleware(15, 60), getDevices);
router.delete('/devices/:deviceId', requireAuth, rateLimitMiddleware(10, 60), idempotency, revokeDevice);
router.post('/logout-all',          requireAuth, rateLimitMiddleware(5, 60, { failOpen: false }), idempotency, logoutEverywhere);

router.get('/history',    requireAuth, rateLimitMiddleware(15, 60), getPlayHistory);
router.delete('/history', requireAuth, rateLimitMiddleware(5, 60), idempotency, clearPlayHistory);

router.get('/export', requireAuth, rateLimitMiddleware(2, 3600, { failOpen: false }), exportUserData);

router.delete('/account', requireAuth, rateLimitMiddleware(3, 3600, { failOpen: false }), deleteAccount);

module.exports = router;