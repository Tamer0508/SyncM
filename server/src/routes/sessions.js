const express = require('express');
const router = express.Router();
const { createSession, getMySessions, addTracks, rateTrack, endSession, respondToInvite, getMyInvites } = require('../controllers/sessionController');

router.get('/', getMySessions);
router.post('/', createSession);
router.post('/:sessionId/tracks', addTracks);
router.post('/tracks/:trackId/rate', rateTrack);
router.patch('/:sessionId/end', endSession);
router.get('/invites', getMyInvites);
router.post('/:sessionId/respond', respondToInvite);

module.exports = router;
