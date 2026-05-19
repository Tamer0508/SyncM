const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');

router.post('/import', playlistController.importPlaylist);
router.get('/', playlistController.getUserPlaylists);

module.exports = router;
