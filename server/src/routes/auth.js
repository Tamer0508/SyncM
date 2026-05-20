const express = require('express');
const router = express.Router();
const { 
  login, 
  callback, 
  getMe, 
  logout, 
  googleAuth, 
  getSettings, 
  updateSettings,
  updateProfile
} = require('../controllers/authController');

router.get('/login', login);
router.get('/callback', callback);
router.get('/me', getMe);
router.get('/logout', logout);
router.post('/google', googleAuth);

router.get('/settings', getSettings);
router.patch('/settings', updateSettings);

router.patch('/profile', updateProfile);

module.exports = router;