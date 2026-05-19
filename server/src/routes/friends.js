const express = require('express');
const router = express.Router();
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

router.get('/search', searchUsers);
router.get('/', getFriends);
router.get('/requests', getIncomingRequests);
router.get('/user/:userId', getUserById);
router.post('/request', sendRequest);
router.patch('/:friendshipId/accept', acceptRequest);
router.delete('/:friendshipId', deleteRequest);
router.delete('/by-user/:friendId', deleteFriendByUserId);

module.exports = router;
