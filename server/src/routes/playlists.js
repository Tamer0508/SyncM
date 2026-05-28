const express = require('express');
const router = express.Router();
const playlistController = require('../controllers/playlistController');

router.post('/custom', playlistController.createCustomPlaylist);
router.get('/', playlistController.getUserPlaylists);
router.post('/import', playlistController.importPlaylist);
router.delete('/:playlistId', playlistController.deletePlaylist);
router.post('/:playlistId/tracks', playlistController.addTrackToPlaylist);
router.post('/liked/toggle', playlistController.toggleLike);
router.get('/liked', playlistController.getLikedTracks);
router.post('/:playlistId/tracks', playlistController.addTrackToPlaylist);
router.delete('/:playlistId/tracks/:trackUri', playlistController.removeTrackFromPlaylist);
router.get('/:playlistId/tracks', playlistController.getPlaylistTracks);
router.post('/history', playlistController.logPlay);

module.exports = router;