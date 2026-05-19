const express = require('express');
const router = express.Router();
const {
  createSession,
  getMySessions,
  addTracks,
  rateTrack,
  endSession,
} = require('../controllers/sessionController');

router.get('/', getMySessions);
router.post('/', createSession);
router.post('/:sessionId/tracks', addTracks);
router.post('/tracks/:trackId/rate', rateTrack);
router.patch('/:sessionId/end', endSession);

module.exports = router;
