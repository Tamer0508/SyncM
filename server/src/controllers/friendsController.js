const prisma = require('../db/prisma');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const searchUsers = async (req, res) => {
  const { query } = req.query;
  if (!query) return res.status(400).json({ error: 'Введите имя для поиска' });

  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const users = await prisma.user.findMany({
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

    res.json(users.map((u) => {
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
        avatarUrl: u.spotifyUser?.avatarUrl || null,
        friendshipStatus
      };
    }));
  } catch (error) {
    console.error('Search error:', error);
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
      return res.status(400).json({ error: existing.status === 'accepted' ? 'Вы уже друзья' : 'Заявка уже существует' });
    }

    const friendship = await prisma.friendship.create({
      data: { senderId, receiverId },
      include: {
        receiver: {
          select: {
            id: true,
            username: true,
            spotifyUser: { select: { avatarUrl: true } }
          }
        }
      }
    });

    res.status(201).json({
      id: friendship.id,
      receiver: {
        id: friendship.receiver.id,
        displayName: friendship.receiver.username,
        avatarUrl: friendship.receiver.spotifyUser?.avatarUrl || null
      },
      status: friendship.status,
      createdAt: friendship.createdAt
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка отправки заявки', details: error.message });
  }
};

const acceptRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = getUserId(req);

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const updated = await prisma.$transaction(async (tx) => {
      const friendship = await tx.friendship.findUnique({
        where: { id: friendshipId }
      });

      if (!friendship || friendship.receiverId !== userId) {
        throw new Error('Заявка не найдена или нет доступа');
      }

      const updatedFriendship = await tx.friendship.update({
        where: { id: friendshipId },
        data: { status: 'accepted' },
        include: { sender: { select: { id: true, username: true, spotifyUser: { select: { avatarUrl: true } } } } }
      });

      await tx.user.updateMany({
        where: { id: { in: [friendship.senderId, friendship.receiverId] } },
        data: { friendsCount: { increment: 1 } }
      });

      return updatedFriendship;
    });

    res.json({
      id: updated.id,
      sender: {
        id: updated.sender.id,
        displayName: updated.sender.username,
        avatarUrl: updated.sender.spotifyUser?.avatarUrl || null
      },
      status: updated.status
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка принятия заявки', details: error.message });
  }
};

const getFriends = async (req, res) => {
  const userId = getUserId(req);
  const { cursor, limit = 20 } = req.query;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
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
        avatarUrl: friendData.spotifyUser?.avatarUrl || null,
        friendshipId: f.id,
        isOnline: friendData.isOnlineHidden ? false : (friendData.isOnline ?? false),
        lastSeenAt: friendData.isOnlineHidden ? null : friendData.lastSeenAt,
      };
    });

    const nextCursor = friendships.length === Number(limit) ? friendships[friendships.length - 1].id : null;
    res.json({ items: friends, nextCursor });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения друзей', details: error.message });
  }
};

const getUserById = async (req, res) => {
  const { userId } = req.params;

  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { spotifyUser: { select: { avatarUrl: true, displayName: true } } }
    });
    if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

    res.json({
      id: user.id,
      displayName: user.username,
      avatarUrl: user.spotifyUser?.avatarUrl || null,
      friendsCount: user.isFriendsHidden ? 0 : user.friendsCount,
      isOnline: user.isOnlineHidden ? false : (user.isOnline ?? false),
      lastSeenAt: user.isOnlineHidden ? null : user.lastSeenAt,
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения пользователя' });
  }
};

const getIncomingRequests = async (req, res) => {
  const userId = getUserId(req);
  const { cursor, limit = 20 } = req.query;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
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
        avatarUrl: r.sender.spotifyUser?.avatarUrl || null
      },
      status: r.status,
      createdAt: r.createdAt
    }));

    const nextCursor = requests.length === Number(limit) ? requests[requests.length - 1].id : null;
    res.json({ items, nextCursor });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения заявок' });
  }
};

const deleteRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const friendship = await prisma.friendship.findUnique({ where: { id: friendshipId } });
    if (!friendship) return res.status(404).json({ error: 'Не найдено' });

    if (friendship.status === 'accepted') {
      return res.status(400).json({ error: 'Для удаления друга используйте /friends/by-user/:friendId' });
    }
    if (friendship.senderId !== userId && friendship.receiverId !== userId) {
      return res.status(403).json({ error: 'Нет доступа' });
    }

    await prisma.friendship.delete({ where: { id: friendshipId } });
    res.json({ message: 'Удалено' });
  } catch (error) {
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

    await prisma.$transaction([
      prisma.friendship.delete({ where: { id: friendship.id } }),
      prisma.user.updateMany({
        where: { id: { in: [friendship.senderId, friendship.receiverId] } },
        data: { friendsCount: { decrement: 1 } }
      })
    ]);
    res.json({ message: 'Друг удален' });
  } catch (error) {
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
