const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');

router.post('/custom', rateLimitMiddleware(10, 60), playlistController.createCustomPlaylist);
router.get('/', rateLimitMiddleware(15, 60), playlistController.getUserPlaylists);
router.post('/import', rateLimitMiddleware(5, 60), playlistController.importPlaylist);
router.delete('/:playlistId', rateLimitMiddleware(10, 60), playlistController.deletePlaylist);
router.post('/:playlistId/tracks', rateLimitMiddleware(30, 60), playlistController.addTrackToPlaylist);
router.post('/liked/toggle', rateLimitMiddleware(20, 60), playlistController.toggleLike);
router.get('/liked', rateLimitMiddleware(15, 60), playlistController.getLikedTracks);
router.delete('/:playlistId/tracks/:trackUri', rateLimitMiddleware(20, 60), playlistController.removeTrackFromPlaylist);
router.get('/:playlistId/tracks', rateLimitMiddleware(15, 60), playlistController.getPlaylistTracks);
router.post('/history', rateLimitMiddleware(30, 60), playlistController.logPlay);

module.exports = router;