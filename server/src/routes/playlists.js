const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');
const { isAuthenticated } = require('../middleware/auth'); // Предполагаем наличие мидлвара для проверки авторизации

router.post('/import', isAuthenticated, playlistController.importPlaylist);
router.get('/', isAuthenticated, playlistController.getUserPlaylists);

module.exports = router;
