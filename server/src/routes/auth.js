const express = require('express');
const router = express.Router();
const { rateLimitMiddleware, ipRateLimitMiddleware } = require('../infrastructure/rateLimiter');
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
} = require('../controllers/authController');

router.get('/login',       ipRateLimitMiddleware(10, 60), login);
router.get('/callback',    ipRateLimitMiddleware(10, 60), callback);
router.post('/google',     ipRateLimitMiddleware(10, 60), googleAuth);
router.get('/google-web',  ipRateLimitMiddleware(10, 60), googleWebLogin);
router.get('/google-callback', ipRateLimitMiddleware(10, 60), googleWebCallback);
router.get('/check-pending',   ipRateLimitMiddleware(10, 60), checkPendingAuth);

router.get('/me',          rateLimitMiddleware(15, 60), getMe);
router.get('/logout',      rateLimitMiddleware(10, 60), logout);
router.post('/avatar',     rateLimitMiddleware(10, 60), uploadAvatar);
router.get('/settings',    rateLimitMiddleware(15, 60), getSettings);
router.patch('/settings',  rateLimitMiddleware(10, 60), updateSettings);
router.patch('/profile',   rateLimitMiddleware(10, 60), updateProfile);

module.exports = router;