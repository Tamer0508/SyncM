const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const idempotency = require('../middleware/idempotency')();
const requireAuth = require('../middleware/requireAuth');

router.use(requireAuth);

router.post('/custom', rateLimitMiddleware(10, 60), idempotency, playlistController.createCustomPlaylist);
router.get('/', rateLimitMiddleware(15, 60), playlistController.getUserPlaylists);
router.post('/import', rateLimitMiddleware(5, 60), idempotency, playlistController.importPlaylist);

router.post('/liked/toggle', rateLimitMiddleware(20, 60), idempotency, playlistController.toggleLike);
router.get('/liked', rateLimitMiddleware(15, 60), playlistController.getLikedTracks);
router.post('/history', rateLimitMiddleware(30, 60), playlistController.logPlay);

router.patch('/:playlistId', rateLimitMiddleware(20, 60), playlistController.updatePlaylist);
router.delete('/:playlistId', rateLimitMiddleware(10, 60), playlistController.deletePlaylist);
router.post('/:playlistId/duplicate', rateLimitMiddleware(5, 60), idempotency, playlistController.duplicatePlaylist);

router.post('/:playlistId/cover', rateLimitMiddleware(10, 60), playlistController.uploadCover);
router.delete('/:playlistId/cover', rateLimitMiddleware(10, 60), playlistController.deleteCover);

router.post('/:playlistId/tracks/bulk', rateLimitMiddleware(20, 60), playlistController.addTracksBulk);
router.put('/:playlistId/tracks/order', rateLimitMiddleware(30, 60), playlistController.reorderTracks);
router.post('/:playlistId/tracks', rateLimitMiddleware(30, 60), playlistController.addTrackToPlaylist);
router.delete('/:playlistId/tracks/:trackUri', rateLimitMiddleware(20, 60), playlistController.removeTrackFromPlaylist);
router.delete('/:playlistId/tracks', rateLimitMiddleware(10, 60), playlistController.clearPlaylist);
router.get('/:playlistId/tracks', rateLimitMiddleware(15, 60), playlistController.getPlaylistTracks);

module.exports = router;
