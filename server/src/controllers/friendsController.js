const { t } = require('../infrastructure/i18n');
const { z } = require('zod');
const prisma = require('../db/prisma');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const { addNotificationJob } = require('../infrastructure/queue');
const { withLock } = require('../infrastructure/lock');
const logger = require('../infrastructure/logger');
const asyncHandler = require('../utils/asyncHandler');
const { normalizePublicId } = require('../utils/publicId');

const invalidateFriendshipCaches = (userIdA, userIdB) =>
  Promise.all([
    incrementVersion(`db:friends-list:${userIdA}`),
    incrementVersion(`db:friends-list:${userIdB}`),
    incrementVersion(`db:user-profile:${userIdA}`),
    incrementVersion(`db:user-profile:${userIdB}`),
  ]);

const invalidateSearchCaches = (userIdA, userIdB) =>
  Promise.all([
    incrementVersion(`db:search-users:${userIdA}`),
    incrementVersion(`db:search-users:${userIdB}`),
  ]);

const FRIEND_USER_FIELDS = {
  id: true,
  username: true,
  customAvatarUrl: true,
  isOnline: true,
  isOnlineHidden: true,
  lastSeenAt: true,
  spotifyUser: { select: { avatarUrl: true, displayName: true } },
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
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { query } = searchQuerySchema.parse(req.query);

  const publicId = normalizePublicId(query);

  const users = await getOrSet(`db:search-users:${userId}`, query.toLowerCase(), 120, async () => {
    const found = await prisma.user.findMany({
      where: {
        id: { not: userId },

        OR: [
          ...(publicId ? [{ publicId }] : []),
          {
            username: { contains: query, mode: 'insensitive' },
            OR: [
              { isSearchHidden: false },
              { sentRequests: { some: { receiverId: userId, status: 'accepted' } } },
              { receivedRequests: { some: { senderId: userId, status: 'accepted' } } },
            ],
          },
        ],

        blocksMade: { none: { blockedId: userId } },
        blocksReceived: { none: { blockerId: userId } },
      },
      take: 20,
      orderBy: { username: 'asc' },
      select: {
        id: true,
        publicId: true,
        username: true,
        customAvatarUrl: true,
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
      const theySentToMe = u.sentRequests[0];
      const iSentToThem = u.receivedRequests[0];

      let friendshipStatus = 'none';
      if (theySentToMe?.status === 'accepted' || iSentToThem?.status === 'accepted') {
        friendshipStatus = 'friends';
      } else if (iSentToThem?.status === 'pending') {
        friendshipStatus = 'sent';
      } else if (theySentToMe?.status === 'pending') {
        friendshipStatus = 'received';
      }
      return {
        id: u.id,
        publicId: u.publicId,
        displayName: u.username,
        avatarUrl: u.customAvatarUrl || u.spotifyUser?.avatarUrl || null,
        friendshipStatus,
      };
    });
  });

  res.json(users);
});

const sendRequest = asyncHandler(async (req, res) => {
  const senderId = req.userId;
  if (!senderId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { receiverId } = sendRequestBodySchema.parse(req.body);

  if (senderId === receiverId) {
    return res.status(400).json({ error: t(req, 'cannotAddSelf') });
  }

  // Существование получателя проверяем здесь, как это делает blockUser.
  // Без проверки заявка несуществующему пользователю падала на внешнем ключе,
  // а у общего обработчика ветки под P2003 нет — клиент получал 500.
  const receiver = await prisma.user.findUnique({
    where: { id: receiverId },
    select: { id: true },
  });
  if (!receiver) return res.status(404).json({ error: t(req, 'userNotFound') });

  const blocked = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: senderId, blockedId: receiverId },
        { blockerId: receiverId, blockedId: senderId },
      ],
    },
    select: { id: true },
  });
  if (blocked) {
    return res.status(400).json({ error: t(req, 'requestFailed') });
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
      data: { senderId, receiverId, pairKey },
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

    await Promise.all([
      incrementVersion(`db:friend-requests:${receiverId}`),
      incrementVersion(`db:search-users:${senderId}`),
      incrementVersion(`db:search-users:${receiverId}`),
    ]);

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
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { friendshipId } = friendshipIdParamsSchema.parse(req.params);

  await withLock(`friendship:${friendshipId}`, 5000, async () => {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship || friendship.receiverId !== userId) {
      return res.status(404).json({ error: t(req, 'requestNotFound') });
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

    await Promise.all([
      incrementVersion(`db:friend-requests:${userId}`),
      invalidateFriendshipCaches(friendship.senderId, friendship.receiverId),
    ]);

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
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { cursor, limit } = cursorLimitSchema.parse(req.query);

  const result = await getOrSet(`db:friends-list:${userId}`, `${cursor || '0'}:${limit}`, 120, async () => {
    const friendships = await prisma.friendship.findMany({
      where: {
        status: 'accepted',
        OR: [{ senderId: userId }, { receiverId: userId }],
        ...(cursor && { id: { lt: cursor } }),
      },
      select: {
        id: true,
        senderId: true,
        sender: { select: FRIEND_USER_FIELDS },
        receiver: { select: FRIEND_USER_FIELDS },
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

  const user = await getOrSet(`db:user-profile:${targetUserId}`, 'profile', 300, async () => {
    const found = await prisma.user.findUnique({
      where: { id: targetUserId },
      select: {
        id: true,
        username: true,
        customAvatarUrl: true,
        friendsCount: true,
        isFriendsHidden: true,
        isOnline: true,
        isOnlineHidden: true,
        lastSeenAt: true,
        spotifyUser: { select: { avatarUrl: true, displayName: true } },
      },
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
    return res.status(404).json({ error: t(req, 'userNotFound') });
  }

  res.json(user);
});

const getIncomingRequests = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { cursor, limit } = cursorLimitSchema.parse(req.query);

  const result = await getOrSet(`db:friend-requests:${userId}`, `${cursor || '0'}:${limit}`, 120, async () => {
    const requests = await prisma.friendship.findMany({
      where: {
        receiverId: userId,
        status: 'pending',
        ...(cursor && { id: { lt: cursor } }),
      },
      select: {
        id: true,
        status: true,
        createdAt: true,
        sender: {
          select: {
            id: true,
            username: true,
            customAvatarUrl: true,
            spotifyUser: { select: { avatarUrl: true } },
          },
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
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { friendshipId } = friendshipIdParamsSchema.parse(req.params);

  await withLock(`friendship:${friendshipId}`, 5000, async () => {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship) return res.status(404).json({ error: t(req, 'notFound') });

    if (friendship.status === 'accepted') {
      return res.status(400).json({ error: t(req, 'useFriendsByUser') });
    }
    if (friendship.senderId !== userId && friendship.receiverId !== userId) {
      return res.status(403).json({ error: t(req, 'forbidden') });
    }

    await prisma.friendship.delete({ where: { id: friendshipId } });
    await incrementVersion(`db:friend-requests:${friendship.receiverId}`);

    res.json({ message: 'Удалено' });
  });
});

const deleteFriendByUserId = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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

  if (!friendship) return res.status(404).json({ error: t(req, 'friendshipNotFound') });

  await withLock(`friendship:${friendship.id}`, 5000, async () => {
    try {
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
    } catch (err) {
      if (err.code === 'P2025') {
        return res.status(404).json({ error: t(req, 'friendshipAlreadyRemoved') });
      }
      throw err;
    }

    await invalidateFriendshipCaches(friendship.senderId, friendship.receiverId);

    res.json({ message: 'Друг удален' });
  });
});


const blockUser = asyncHandler(async (req, res) => {
  const blockerId = req.userId;
  const { userId: blockedId } = userIdParamsSchema.parse(req.params);

  if (blockerId === blockedId) {
    return res.status(400).json({ error: t(req, 'cannotBlockSelf') });
  }

  const target = await prisma.user.findUnique({
    where: { id: blockedId },
    select: { id: true },
  });
  if (!target) return res.status(404).json({ error: t(req, 'userNotFound') });

  await prisma.$transaction(async (tx) => {
    await tx.block.upsert({
      where: { blockerId_blockedId: { blockerId, blockedId } },
      create: { blockerId, blockedId },
      update: {},
    });

    const between = {
      OR: [
        { senderId: blockerId, receiverId: blockedId },
        { senderId: blockedId, receiverId: blockerId },
      ],
    };

    const acceptedCount = await tx.friendship.count({
      where: { ...between, status: 'accepted' },
    });

    // Дружба и заявки в обе стороны.
    await tx.friendship.deleteMany({ where: between });

    if (acceptedCount > 0) {
      await tx.user.updateMany({
        where: { id: { in: [blockerId, blockedId] }, friendsCount: { gt: 0 } },
        data: { friendsCount: { decrement: 1 } },
      });
    }
  });

  await Promise.all([
    incrementVersion(`db:friends-list:${blockerId}`),
    incrementVersion(`db:friends-list:${blockedId}`),
    incrementVersion(`db:friend-requests:${blockerId}`),
    incrementVersion(`db:friend-requests:${blockedId}`),
    invalidateSearchCaches(blockerId, blockedId),
  ]);

  logger.info({ blockerId, blockedId }, 'User blocked');
  res.json({ message: 'Пользователь заблокирован' });
});

const unblockUser = asyncHandler(async (req, res) => {
  const blockerId = req.userId;
  const { userId: blockedId } = userIdParamsSchema.parse(req.params);

  await prisma.block.deleteMany({ where: { blockerId, blockedId } });

  await Promise.all([
    invalidateSearchCaches(blockerId, blockedId),
  ]);

  res.json({ message: 'Пользователь разблокирован' });
});

const getBlockedUsers = asyncHandler(async (req, res) => {
  const blockerId = req.userId;

  const blocks = await prisma.block.findMany({
    where: { blockerId },
    orderBy: { createdAt: 'desc' },
    take: 100,
    include: {
      blocked: {
        select: {
          id: true,
          username: true,
          customAvatarUrl: true,
          spotifyUser: { select: { avatarUrl: true } },
        },
      },
    },
  });

  res.json(
    blocks.map((b) => ({
      id: b.blocked.id,
      displayName: b.blocked.username,
      avatarUrl: b.blocked.customAvatarUrl || b.blocked.spotifyUser?.avatarUrl || null,
      blockedAt: b.createdAt,
    }))
  );
});


const getUserActivity = asyncHandler(async (req, res) => {
  const viewerId = req.userId;
  const { userId: targetId } = userIdParamsSchema.parse(req.params);

  if (viewerId === targetId) return res.json({ history: [], likedCount: 0 });

  const [target, friendship, blocked] = await Promise.all([
    prisma.user.findUnique({
      where: { id: targetId },
      select: { isActivityHidden: true },
    }),
    prisma.friendship.findFirst({
      where: {
        status: 'accepted',
        OR: [
          { senderId: viewerId, receiverId: targetId },
          { senderId: targetId, receiverId: viewerId },
        ],
      },
      select: { id: true },
    }),
    prisma.block.findFirst({
      where: {
        OR: [
          { blockerId: viewerId, blockedId: targetId },
          { blockerId: targetId, blockedId: viewerId },
        ],
      },
      select: { id: true },
    }),
  ]);

  if (!target) return res.status(404).json({ error: t(req, 'userNotFound') });

  if (target.isActivityHidden || blocked || !friendship) {
    return res.json({ history: [], likedCount: 0 });
  }

  const [rows, likedCount] = await Promise.all([
    prisma.playHistory.findMany({
      where: { userId: targetId },
      orderBy: { playedAt: 'desc' },
      take: 40,
      select: { spotifyUri: true, trackName: true, artistName: true, playedAt: true },
    }),
    prisma.likedTrack.count({ where: { userId: targetId } }),
  ]);

  // Схлопываем повторы: одна песня встречается в истории десятки раз подряд.
  const seen = new Set();
  const history = [];
  for (const row of rows) {
    if (seen.has(row.spotifyUri)) continue;
    seen.add(row.spotifyUri);
    history.push(row);
    if (history.length >= 10) break;
  }

  res.json({ history, likedCount });
});

module.exports = {

  blockUser,

  unblockUser,

  getBlockedUsers,

  getUserActivity,
  searchUsers,
  sendRequest,
  acceptRequest,
  getFriends,
  getUserById,
  getIncomingRequests,
  deleteRequest,
  deleteFriendByUserId,
};