const prisma = require('../db/prisma');

const getUserId = (req) => {
  console.log('getUserId - auth header:', req.headers.authorization);
  console.log('getUserId - session userId:', req.session?.userId);
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
    const users = await prisma.appUser.findMany({
      where: {
        username: { contains: query, mode: 'insensitive' },
        id: { not: userId }
      },
      include: {
        User: { select: { avatarUrl: true } },
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
        avatarUrl: u.User?.avatarUrl || null,
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
    const friendship = await prisma.friendship.create({
      data: { senderId, receiverId },
      include: {
        receiver: {
          select: {
            id: true,
            username: true,
            User: { select: { avatarUrl: true } }
          }
        }
      }
    });

    res.status(201).json({
      id: friendship.id,
      receiver: {
        id: friendship.receiver.id,
        displayName: friendship.receiver.username,
        avatarUrl: friendship.receiver.User?.avatarUrl || null
      },
      status: friendship.status,
      createdAt: friendship.createdAt
    });
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ error: 'Заявка уже существует' });
    }
    if (error.code === 'P2025') {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    console.error('Send request error:', error);
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
        where: { id: friendshipId },
        include: {
          sender: { select: { id: true, username: true, User: { select: { avatarUrl: true } } } },
          receiver: { select: { id: true } }
        }
      });

      if (!friendship) {
        const err = new Error('Заявка не найдена');
        err.status = 404;
        throw err;
      }

      if (friendship.receiverId !== userId) {
        const err = new Error('Нет доступа');
        err.status = 403;
        throw err;
      }

      if (friendship.status !== 'pending') {
        const err = new Error('Заявка уже обработана');
        err.status = 400;
        throw err;
      }

      const updatedFriendship = await tx.friendship.update({
        where: { id: friendshipId },
        data: { status: 'accepted' },
        include: { sender: { select: { id: true, username: true, User: { select: { avatarUrl: true } } } } }
      });

      await tx.appUser.updateMany({
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
        avatarUrl: updated.sender.User?.avatarUrl || null
      },
      status: updated.status
    });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ error: error.message });
    }
    console.error('Accept request error:', error);
    res.status(500).json({ error: 'Ошибка принятия заявки', details: error.message });
  }
};

const deleteRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = getUserId(req);

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId }
    });

    if (!friendship) return res.status(404).json({ error: 'Не найдено' });

    if (friendship.senderId !== userId && friendship.receiverId !== userId) {
      return res.status(403).json({ error: 'Нет доступа' });
    }

    await prisma.friendship.delete({ where: { id: friendshipId } });
    res.json({ message: 'Удалено' });
  } catch (error) {
    console.error('Delete request error:', error);
    res.status(500).json({ error: 'Ошибка удаления', details: error.message });
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
      prisma.appUser.updateMany({
        where: { id: { in: [friendship.senderId, friendship.receiverId] } },
        data: { friendsCount: { decrement: 1 } }
      })
    ]);
    res.json({ message: 'Друг удален' });
  } catch (error) {
    console.error('Delete friend error:', error);
    res.status(500).json({ error: 'Ошибка удаления', details: error.message });
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
        OR: [
          { senderId: userId },
          { receiverId: userId }
        ],
        ...(cursor && { id: { lt: cursor } })
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            User: { select: { avatarUrl: true, displayName: true } }
          }
        },
        receiver: {
          select: {
            id: true,
            username: true,
            User: { select: { avatarUrl: true, displayName: true } }
          }
        }
      },
      orderBy: { id: 'desc' },
      take: Number(limit)
    });

    const friends = friendships.map(f => {
      const friendData = f.senderId === userId ? f.receiver : f.sender;
      return {
        id: friendData.id,
        displayName: friendData.username,
        spotifyDisplayName: friendData.User?.displayName || null,
        avatarUrl: friendData.User?.avatarUrl || null,
        friendshipId: f.id,
      };
    });

    const nextCursor = friendships.length === Number(limit)
      ? friendships[friendships.length - 1].id
      : null;

    res.json({ items: friends, nextCursor });
  } catch (error) {
    console.error('Get friends error:', error);
    res.status(500).json({ error: 'Ошибка получения друзей', details: error.message });
  }
};

const getIncomingRequests = async (req, res) => {
  const userId = getUserId(req);
  const { cursor, limit = 20 } = req.query;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const requests = await prisma.friendship.findMany({
      where: { receiverId: userId, status: 'pending',
        ...(cursor && { id: { lt: cursor } })
       },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            User: { select: { avatarUrl: true } }
          }
        }
      },
      orderBy: { id: 'desc' },
      take: Number(limit)
    });

    const nextCursor = requests.length === Number(limit)
      ? requests[requests.length - 1].id
      : null;

    const items = requests.map(r => ({
      id: r.id,
      sender: {
        id: r.sender.id,
        displayName: r.sender.username,
        avatarUrl: r.sender.User?.avatarUrl || null
      },
      status: r.status,
      createdAt: r.createdAt
    }));

    res.json({ items, nextCursor });
  } catch (error) {
    console.error('Get incoming requests error:', error);
    res.status(500).json({ error: 'Ошибка получения заявок', details: error.message });
  }
};

module.exports = {
  searchUsers,
  sendRequest,
  acceptRequest,
  deleteRequest,
  deleteFriendByUserId,
  getFriends,
  getIncomingRequests,
};
