const express = require('express');
const router = express.Router();
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const {
  searchUsers,
  sendRequest,
  acceptRequest,
  deleteRequest,
  getUserById,
  deleteFriendByUserId,
  getFriends,
  getIncomingRequests,
} = require('../controllers/friendsController');

router.get('/search', rateLimitMiddleware(15, 60), searchUsers);
router.get('/', rateLimitMiddleware(15, 60), getFriends);
router.get('/requests', rateLimitMiddleware(15, 60), getIncomingRequests);
router.get('/user/:userId', rateLimitMiddleware(15, 60), getUserById);
router.post('/request', rateLimitMiddleware(10, 60), sendRequest);
router.patch('/:friendshipId/accept', rateLimitMiddleware(10, 60), acceptRequest);
router.delete('/:friendshipId', rateLimitMiddleware(10, 60), deleteRequest);
router.delete('/by-user/:friendId', rateLimitMiddleware(10, 60), deleteFriendByUserId);

module.exports = router;
