const express = require('express');
const router = express.Router();
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const idempotency = require('../middleware/idempotency')();
const requireAuth = require('../middleware/requireAuth');
const {
  createSession,
  getMySessions,
  addTracks,
  rateTrack,
  endSession,
  respondToInvite,
  getMyInvites
} = require('../controllers/sessionController');

router.use(requireAuth);

router.get('/',                    rateLimitMiddleware(20, 60), getMySessions);
router.post('/',                   rateLimitMiddleware(5, 60),  idempotency, createSession);
router.post('/:sessionId/tracks',  rateLimitMiddleware(30, 60), idempotency, addTracks);
router.post('/tracks/:trackId/rate', rateLimitMiddleware(30, 60), idempotency, rateTrack);
router.patch('/:sessionId/end',    rateLimitMiddleware(10, 60), idempotency, endSession);
router.get('/invites',             rateLimitMiddleware(20, 60), getMyInvites);
router.post('/:sessionId/respond', rateLimitMiddleware(15, 60), idempotency, respondToInvite);

module.exports = router;