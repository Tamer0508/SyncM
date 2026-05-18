const express = require('express');
const router = express.Router();
const { login, callback, getMe, logout, getSettings, updateSettings, googleAuth } = require('../controllers/authController');

router.get('/login', login);
router.get('/callback', callback);
router.get('/me', getMe);
router.get('/logout', logout);
router.get('/settings', getSettings);
router.patch('/settings', updateSettings);
router.post('/google', googleAuth);

module.exports = router;