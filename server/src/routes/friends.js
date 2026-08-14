const express = require('express');
const router = express.Router();
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const idempotency = require('../middleware/idempotency')();
const requireAuth = require('../middleware/requireAuth');
const {
  searchUsers,
  sendRequest,
  acceptRequest,
  deleteRequest,
  getUserById,
  deleteFriendByUserId,

  blockUser,

  unblockUser,

  getBlockedUsers,

  getUserActivity,
  getFriends,
  getIncomingRequests,
} = require('../controllers/friendsController');

router.use(requireAuth);

router.get('/search', rateLimitMiddleware(15, 60), searchUsers);
router.get('/', rateLimitMiddleware(15, 60), getFriends);
router.get('/requests', rateLimitMiddleware(15, 60), getIncomingRequests);
router.get('/user/:userId', rateLimitMiddleware(15, 60), getUserById);
router.get('/user/:userId/activity', rateLimitMiddleware(15, 60), getUserActivity);
router.post('/request', rateLimitMiddleware(10, 60), idempotency, sendRequest);
router.patch('/:friendshipId/accept', rateLimitMiddleware(10, 60), idempotency, acceptRequest);
router.delete('/:friendshipId', rateLimitMiddleware(10, 60), idempotency, deleteRequest);
router.delete('/by-user/:friendId', rateLimitMiddleware(10, 60), idempotency, deleteFriendByUserId);

router.get('/blocked', rateLimitMiddleware(15, 60), getBlockedUsers);
router.post('/blocked/:userId', rateLimitMiddleware(10, 60), idempotency, blockUser);
router.delete('/blocked/:userId', rateLimitMiddleware(10, 60), idempotency, unblockUser);

module.exports = router;