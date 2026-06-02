const prisma = require('../db/prisma');
const { getOrSet, invalidateUserDB } = require('../infrastructure/spotify/cache');
const { addNotificationJob } = require('../infrastructure/queue');
const { withLock } = require('../infrastructure/lock');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const searchUsers = async (req, res) => {
  let { query } = req.query;
  if (!query) return res.status(400).json({ error: 'Введите имя для поиска' });

  query = query.trim().substring(0, 100);
  if (query.length === 0) return res.status(400).json({ error: 'Введите имя для поиска' });

  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:search-users:${query.toLowerCase()}:${userId}`;

  try {
    const users = await getOrSet(cacheKey, 120, async () => {
      const found = await prisma.user.findMany({
        where: {
          username: { contains: query, mode: 'insensitive' },
          id: { not: userId }
        },
        include: {
          spotifyUser: { select: { avatarUrl: true } },
          sentRequests: {
            where: { receiverId: userId },
            select: { id: true, status: true }
          },
          receivedRequests: {
            where: { senderId: userId },
            select: { id: true, status: true }
          }
        }
      });

      return found.map((u) => {
        const sent = u.sentRequests[0];
        const received = u.receivedRequests[0];
        let friendshipStatus = 'none';
        if (sent?.status === 'accepted' || received?.status === 'accepted') {
          friendshipStatus = 'friends';
        } else if (sent?.status === 'pending') {
          friendshipStatus = 'sent';
        } else if (received?.status === 'pending') {
          friendshipStatus = 'received';
        }
        return {
          id: u.id,
          displayName: u.username,
          avatarUrl: u.customAvatarUrl || u.spotifyUser?.avatarUrl || null,
          friendshipStatus
        };
      });
    });

    res.json(users);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Search error:', error);
    }
    res.status(500).json({ error: 'Ошибка поиска', details: error.message });
  }
};

const sendRequest = async (req, res) => {
  const { receiverId } = req.body;
  const senderId = getUserId(req);

  if (!senderId) return res.status(401).json({ error: 'Не авторизован' });
  if (!receiverId) return res.status(400).json({ error: 'receiverId обязателен' });
  if (senderId === receiverId) return res.status(400).json({ error: 'Нельзя добавить себя' });

  try {
    // Use pair-level lock to avoid duplicate concurrent friend requests
    const pairKey = [senderId, receiverId].sort().join(':');
    await withLock(`friendship:pair:${pairKey}`, 5000, async () => {
      const existing = await prisma.friendship.findFirst({
        where: {
          OR: [
            { senderId, receiverId },
            { senderId: receiverId, receiverId: senderId }
          ],
          status: { in: ['pending', 'accepted'] }
        }
      });

      if (existing) {
        // Respond with same semantics
        res.status(400).json({ error: existing.status === 'accepted' ? 'Вы уже друзья' : 'Заявка уже существует' });
        return;
      }

      const friendship = await prisma.friendship.create({
        data: { senderId, receiverId },
        include: {
          sender: { select: { id: true, username: true } },
          receiver: {
            select: {
              id: true,
              username: true,
              customAvatarUrl: true,
              spotifyUser: { select: { avatarUrl: true } }
            }
          }
        }
      });

      await invalidateUserDB(senderId);
      await invalidateUserDB(receiverId);

      await addNotificationJob({
        type: 'friend_request',
        toUserId: receiverId,
        fromUserId: senderId,
        fromUserName: friendship.sender.username,
        requestId: friendship.id,
        timestamp: Date.now(),
      });

      res.status(201).json({
        id: friendship.id,
        receiver: {
          id: friendship.receiver.id,
          displayName: friendship.receiver.username,
          avatarUrl: friendship.receiver.customAvatarUrl || friendship.receiver.spotifyUser?.avatarUrl || null
        },
        status: friendship.status,
        createdAt: friendship.createdAt
      });
    });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Send request error:', error);
    }
    res.status(500).json({ error: 'Ошибка отправки заявки', details: error.message });
  }
};

const acceptRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = getUserId(req);

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    await withLock(`friendship:${friendshipId}`, 5000, async () => {
      const friendship = await prisma.friendship.findUnique({ where: { id: friendshipId } });

      if (!friendship || friendship.receiverId !== userId) {
        // Not found or no access — respond and return
        res.status(404).json({ error: 'Заявка не найдена или нет доступа' });
        return;
      }

      const updated = await prisma.$transaction(async (tx) => {
        const updatedFriendship = await tx.friendship.update({
          where: { id: friendshipId },
          data: { status: 'accepted' },
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                customAvatarUrl: true,
                spotifyUser: { select: { avatarUrl: true } },
              },
            },
          },
        });

        await tx.user.updateMany({
          where: { id: { in: [friendship.senderId, friendship.receiverId] } },
          data: { friendsCount: { increment: 1 } },
        });

        return updatedFriendship;
      });

      await invalidateUserDB(friendship.senderId);
      await invalidateUserDB(friendship.receiverId);

      await addNotificationJob({
        type: 'friend_request_accepted',
        toUserId: friendship.senderId,
        fromUserId: userId,
        fromUserName: updated.sender.username,
        friendshipId: updated.id,
        timestamp: Date.now(),
      });

      res.json({
        id: updated.id,
        sender: {
          id: updated.sender.id,
          displayName: updated.sender.username,
          avatarUrl:
            updated.sender.customAvatarUrl ||
            updated.sender.spotifyUser?.avatarUrl ||
            null,
        },
        status: updated.status,
      });
    });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Accept request error:', error);
    }
    res.status(500).json({ error: 'Ошибка принятия заявки', details: error.message });
  }
};

const getFriends = async (req, res) => {
  const userId = getUserId(req);
  const { cursor, limit = 20 } = req.query;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:friends-list:${userId}:${cursor || '0'}:${limit}`;

  try {
    const result = await getOrSet(cacheKey, null, async () => {
      const friendships = await prisma.friendship.findMany({
        where: {
          status: 'accepted',
          OR: [{ senderId: userId }, { receiverId: userId }],
          ...(cursor && { id: { lt: cursor } })
        },
        include: {
          sender: { include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } } },
          receiver: { include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } } }
        },
        orderBy: { id: 'desc' },
        take: Number(limit)
      });

      const friends = friendships.map(f => {
        const friendData = f.senderId === userId ? f.receiver : f.sender;
        return {
          id: friendData.id,
          displayName: friendData.username,
          spotifyDisplayName: friendData.spotifyUser?.displayName || null,
          avatarUrl: friendData.customAvatarUrl || friendData.spotifyUser?.avatarUrl || null,
          friendshipId: f.id,
          isOnline: friendData.isOnlineHidden ? false : (friendData.isOnline ?? false),
          lastSeenAt: friendData.isOnlineHidden ? null : friendData.lastSeenAt,
        };
      });

      const nextCursor = friendships.length === Number(limit) ? friendships[friendships.length - 1].id : null;
      return { items: friends, nextCursor };
    });

    res.json(result);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Get friends error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения друзей', details: error.message });
  }
};

const getUserById = async (req, res) => {
  const { userId: targetUserId } = req.params;
  const cacheKey = `db:user-profile:${targetUserId}`;

  try {
    const user = await getOrSet(cacheKey, null, async () => {
      const found = await prisma.user.findUnique({
        where: { id: targetUserId },
        include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } },
      });

      if (!found) return null;

      return {
        id: found.id,
        displayName: found.username,
        avatarUrl: found.customAvatarUrl || found.spotifyUser?.avatarUrl || null,
        friendsCount: found.isFriendsHidden ? 0 : found.friendsCount,
        isOnline: found.isOnlineHidden ? false : (found.isOnline ?? false),
        lastSeenAt: found.isOnlineHidden ? null : found.lastSeenAt,
      };
    });

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json(user);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Get user by id error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения пользователя' });
  }
};

const getIncomingRequests = async (req, res) => {
  const userId = getUserId(req);
  const { cursor, limit = 20 } = req.query;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:friend-requests:${userId}:${cursor || '0'}:${limit}`;

  try {
    const result = await getOrSet(cacheKey, null, async () => {
      const requests = await prisma.friendship.findMany({
        where: { receiverId: userId, status: 'pending', ...(cursor && { id: { lt: cursor } }) },
        include: { sender: { include: { spotifyUser: { select: { avatarUrl: true } } } } },
        orderBy: { id: 'desc' },
        take: Number(limit)
      });

      const items = requests.map(r => ({
        id: r.id,
        sender: {
          id: r.sender.id,
          displayName: r.sender.username,
          avatarUrl: r.sender.customAvatarUrl || r.sender.spotifyUser?.avatarUrl || null
        },
        status: r.status,
        createdAt: r.createdAt
      }));

      const nextCursor = requests.length === Number(limit) ? requests[requests.length - 1].id : null;
      return { items, nextCursor };
    });

    res.json(result);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Get incoming requests error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения заявок' });
  }
};

const deleteRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    await withLock(`friendship:${friendshipId}`, 5000, async () => {
      const friendship = await prisma.friendship.findUnique({ where: { id: friendshipId } });
      if (!friendship) return res.status(404).json({ error: 'Не найдено' });

      if (friendship.status === 'accepted') {
        return res.status(400).json({ error: 'Для удаления друга используйте /friends/by-user/:friendId' });
      }
      if (friendship.senderId !== userId && friendship.receiverId !== userId) {
        return res.status(403).json({ error: 'Нет доступа' });
      }

      await prisma.friendship.delete({ where: { id: friendshipId } });

      await invalidateUserDB(userId);
      const otherId = friendship.senderId === userId ? friendship.receiverId : friendship.senderId;
      await invalidateUserDB(otherId);

      res.json({ message: 'Удалено' });
    });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Delete request error:', error);
    }
    res.status(500).json({ error: 'Ошибка удаления' });
  }
};

const deleteFriendByUserId = async (req, res) => {
  const { friendId } = req.params;
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const friendship = await prisma.friendship.findFirst({
      where: {
        status: 'accepted',
        OR: [
          { senderId: userId, receiverId: friendId },
          { senderId: friendId, receiverId: userId },
        ],
      },
    });

    if (!friendship) return res.status(404).json({ error: 'Дружба не найдена' });

    await withLock(`friendship:${friendship.id}`, 5000, async () => {
      await prisma.$transaction([
        prisma.friendship.delete({ where: { id: friendship.id } }),
        prisma.user.updateMany({
          where: { id: { in: [friendship.senderId, friendship.receiverId] } },
          data: { friendsCount: { decrement: 1 } }
        })
      ]);
      await invalidateUserDB(userId);
      await invalidateUserDB(friendId);
      res.json({ message: 'Друг удален' });
    });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Delete friend error:', error);
    }
    res.status(500).json({ error: 'Ошибка удаления' });
  }
};

module.exports = {
  searchUsers,
  sendRequest,
  acceptRequest,
  getFriends,
  getUserById,
  getIncomingRequests,
  deleteRequest,
  deleteFriendByUserId
};
