const express = require('express');
const router = express.Router();
const { 
  login, 
  callback, 
  getMe, 
  logout, 
  googleAuth, 
  getSettings, 
  updateSettings 
} = require('../controllers/authController');

router.get('/login', login);
router.get('/callback', callback);
router.get('/me', getMe);
router.get('/logout', logout);
router.post('/google', googleAuth);

// Настройки приватности
router.get('/settings', getSettings);
router.patch('/settings', updateSettings);

module.exports = router;
