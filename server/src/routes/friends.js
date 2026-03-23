const express = require('express');
const router = express.Router();
const {
  searchUsers,
  sendRequest,
  acceptRequest,
  deleteRequest,
  getFriends,
  getIncomingRequests,
} = require('../controllers/friendsController');

router.get('/search', searchUsers);
router.get('/', getFriends);
router.get('/requests', getIncomingRequests);
router.post('/request', sendRequest);
router.patch('/:friendshipId/accept', acceptRequest);
router.delete('/:friendshipId', deleteRequest);

module.exports = router;