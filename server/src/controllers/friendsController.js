const { z } = require('zod');
const prisma = require('../db/prisma');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const { addNotificationJob } = require('../infrastructure/queue');
const { withLock } = require('../infrastructure/lock');
const asyncHandler = require('../utils/asyncHandler');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const searchQuerySchema = z.object({
  query: z.string().trim().min(1).max(100),
});

const sendRequestBodySchema = z.object({
  receiverId: z.string().min(1, 'receiverId обязателен'),
});

const friendshipIdParamsSchema = z.object({
  friendshipId: z.string().min(1),
});

const cursorLimitSchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const userIdParamsSchema = z.object({
  userId: z.string().min(1),
});

const friendIdParamsSchema = z.object({
  friendId: z.string().min(1),
});


const searchUsers = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { query } = searchQuerySchema.parse(req.query);

  const cacheKey = `db:search-users:${query.toLowerCase()}:${userId}`;

  const users = await getOrSet(cacheKey, 120, async () => {
    const found = await prisma.user.findMany({
      where: {
        username: { contains: query, mode: 'insensitive' },
        id: { not: userId },
      },
      include: {
        spotifyUser: { select: { avatarUrl: true } },
        sentRequests: {
          where: { receiverId: userId },
          select: { id: true, status: true },
        },
        receivedRequests: {
          where: { senderId: userId },
          select: { id: true, status: true },
        },
      },
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
        friendshipStatus,
      };
    });
  });

  res.json(users);
});

const sendRequest = asyncHandler(async (req, res) => {
  const senderId = getUserId(req);
  if (!senderId) return res.status(401).json({ error: 'Не авторизован' });

  const { receiverId } = sendRequestBodySchema.parse(req.body);

  if (senderId === receiverId) {
    return res.status(400).json({ error: 'Нельзя добавить себя' });
  }

  const pairKey = [senderId, receiverId].sort().join(':');
  await withLock(`friendship:pair:${pairKey}`, 5000, async () => {
    const existing = await prisma.friendship.findFirst({
      where: {
        OR: [
          { senderId, receiverId },
          { senderId: receiverId, receiverId: senderId },
        ],
        status: { in: ['pending', 'accepted'] },
      },
    });

    if (existing) {
      return res.status(400).json({
        error: existing.status === 'accepted' ? 'Вы уже друзья' : 'Заявка уже существует',
      });
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
            spotifyUser: { select: { avatarUrl: true } },
          },
        },
      },
    });

    // Инвалидация кэша через глобальное версионирование
    await incrementVersion();

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
        avatarUrl:
          friendship.receiver.customAvatarUrl ||
          friendship.receiver.spotifyUser?.avatarUrl ||
          null,
      },
      status: friendship.status,
      createdAt: friendship.createdAt,
    });
  });
});

const acceptRequest = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { friendshipId } = friendshipIdParamsSchema.parse(req.params);

  await withLock(`friendship:${friendshipId}`, 5000, async () => {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship || friendship.receiverId !== userId) {
      return res.status(404).json({ error: 'Заявка не найдена или нет доступа' });
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

      // Пересчёт friendsCount через COUNT
      const [senderCount, receiverCount] = await Promise.all([
        tx.friendship.count({
          where: {
            status: 'accepted',
            OR: [{ senderId: friendship.senderId }, { receiverId: friendship.senderId }],
          },
        }),
        tx.friendship.count({
          where: {
            status: 'accepted',
            OR: [{ senderId: friendship.receiverId }, { receiverId: friendship.receiverId }],
          },
        }),
      ]);

      await tx.user.update({
        where: { id: friendship.senderId },
        data: { friendsCount: senderCount },
      });
      await tx.user.update({
        where: { id: friendship.receiverId },
        data: { friendsCount: receiverCount },
      });

      return updatedFriendship;
    });

    await incrementVersion();

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
});

const getFriends = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { cursor, limit } = cursorLimitSchema.parse(req.query);
  const cacheKey = `db:friends-list:${userId}:${cursor || '0'}:${limit}`;

  const result = await getOrSet(cacheKey, 120, async () => {
    const friendships = await prisma.friendship.findMany({
      where: {
        status: 'accepted',
        OR: [{ senderId: userId }, { receiverId: userId }],
        ...(cursor && { id: { lt: cursor } }),
      },
      include: {
        sender: {
          include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } },
        },
        receiver: {
          include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } },
        },
      },
      orderBy: { id: 'desc' },
      take: limit,
    });

    const friends = friendships.map((f) => {
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

    const nextCursor =
      friendships.length === limit ? friendships[friendships.length - 1].id : null;
    return { items: friends, nextCursor };
  });

  res.json(result);
});

const getUserById = asyncHandler(async (req, res) => {
  const { userId: targetUserId } = userIdParamsSchema.parse(req.params);
  const cacheKey = `db:user-profile:${targetUserId}`;

  const user = await getOrSet(cacheKey, 300, async () => {
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
});

const getIncomingRequests = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { cursor, limit } = cursorLimitSchema.parse(req.query);
  const cacheKey = `db:friend-requests:${userId}:${cursor || '0'}:${limit}`;

  const result = await getOrSet(cacheKey, 120, async () => {
    const requests = await prisma.friendship.findMany({
      where: {
        receiverId: userId,
        status: 'pending',
        ...(cursor && { id: { lt: cursor } }),
      },
      include: {
        sender: {
          include: { spotifyUser: { select: { avatarUrl: true } } },
        },
      },
      orderBy: { id: 'desc' },
      take: limit,
    });

    const items = requests.map((r) => ({
      id: r.id,
      sender: {
        id: r.sender.id,
        displayName: r.sender.username,
        avatarUrl: r.sender.customAvatarUrl || r.sender.spotifyUser?.avatarUrl || null,
      },
      status: r.status,
      createdAt: r.createdAt,
    }));

    const nextCursor = requests.length === limit ? requests[requests.length - 1].id : null;
    return { items, nextCursor };
  });

  res.json(result);
});

const deleteRequest = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { friendshipId } = friendshipIdParamsSchema.parse(req.params);

  await withLock(`friendship:${friendshipId}`, 5000, async () => {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship) return res.status(404).json({ error: 'Не найдено' });

    if (friendship.status === 'accepted') {
      return res.status(400).json({ error: 'Для удаления друга используйте /friends/by-user/:friendId' });
    }
    if (friendship.senderId !== userId && friendship.receiverId !== userId) {
      return res.status(403).json({ error: 'Нет доступа' });
    }

    await prisma.friendship.delete({ where: { id: friendshipId } });
    await incrementVersion();

    res.json({ message: 'Удалено' });
  });
});

const deleteFriendByUserId = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { friendId } = friendIdParamsSchema.parse(req.params);

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
    await prisma.$transaction(async (tx) => {
      await tx.friendship.delete({ where: { id: friendship.id } });

      // Пересчитываем friendsCount для обоих
      const [senderCount, receiverCount] = await Promise.all([
        tx.friendship.count({
          where: {
            status: 'accepted',
            OR: [{ senderId: friendship.senderId }, { receiverId: friendship.senderId }],
          },
        }),
        tx.friendship.count({
          where: {
            status: 'accepted',
            OR: [{ senderId: friendship.receiverId }, { receiverId: friendship.receiverId }],
          },
        }),
      ]);

      await tx.user.update({
        where: { id: friendship.senderId },
        data: { friendsCount: senderCount },
      });
      await tx.user.update({
        where: { id: friendship.receiverId },
        data: { friendsCount: receiverCount },
      });
    });

    await incrementVersion();

    res.json({ message: 'Друг удален' });
  });
});

module.exports = {
  searchUsers,
  sendRequest,
  acceptRequest,
  getFriends,
  getUserById,
  getIncomingRequests,
  deleteRequest,
  deleteFriendByUserId,
};