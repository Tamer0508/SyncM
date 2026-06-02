const express = require('express');
const router = express.Router();
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const {
  createSession,
  getMySessions,
  addTracks,
  rateTrack,
  endSession,
  respondToInvite,
  getMyInvites
} = require('../controllers/sessionController');

router.get('/',                    rateLimitMiddleware(20, 60), getMySessions);
router.post('/',                   rateLimitMiddleware(5, 60),  createSession);    
router.post('/:sessionId/tracks',  rateLimitMiddleware(30, 60), addTracks);         
router.post('/tracks/:trackId/rate', rateLimitMiddleware(30, 60), rateTrack);
router.patch('/:sessionId/end',    rateLimitMiddleware(10, 60), endSession);
router.get('/invites',             rateLimitMiddleware(20, 60), getMyInvites);
router.post('/:sessionId/respond', rateLimitMiddleware(15, 60), respondToInvite);

module.exports = router;