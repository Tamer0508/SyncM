const prisma = require('../db/prisma');

// Поиск пользователей по имени
const searchUsers = async (req, res) => {
  const { query } = req.query;

  if (!query) {
    return res.status(400).json({ error: 'Введите имя для поиска' });
  }

  try {
    const users = await prisma.user.findMany({
      where: {
        displayName: {
          contains: query,
          mode: 'insensitive',
        },
        NOT: {
          id: req.session.userId, // исключаем себя
        },
      },
      select: {
        id: true,
        displayName: true,
        avatarUrl: true,
      },
    });

    res.json(users);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка поиска' });
  }
};

// Отправить заявку в друзья
const sendRequest = async (req, res) => {
  const { receiverId } = req.body;
  const senderId = req.session.userId;

  if (!senderId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  if (senderId === receiverId) {
    return res.status(400).json({ error: 'Нельзя добавить себя' });
  }

  try {
    // Проверяем что заявка ещё не существует
    const existing = await prisma.friendship.findFirst({
      where: {
        OR: [
          { senderId, receiverId },
          { senderId: receiverId, receiverId: senderId },
        ],
      },
    });

    if (existing) {
      return res.status(400).json({ error: 'Заявка уже существует' });
    }

    const friendship = await prisma.friendship.create({
      data: { senderId, receiverId },
      include: {
        receiver: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
      },
    });

    res.json(friendship);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка отправки заявки' });
  }
};

// Принять заявку
const acceptRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = req.session.userId;

  if (!userId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  try {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship) {
      return res.status(404).json({ error: 'Заявка не найдена' });
    }

    if (friendship.receiverId !== userId) {
      return res.status(403).json({ error: 'Нет доступа' });
    }

    const updated = await prisma.friendship.update({
      where: { id: friendshipId },
      data: { status: 'accepted' },
      include: {
        sender: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
      },
    });

    res.json(updated);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка принятия заявки' });
  }
};

// Отклонить или удалить друга
const deleteRequest = async (req, res) => {
  const { friendshipId } = req.params;
  const userId = req.session.userId;

  if (!userId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  try {
    const friendship = await prisma.friendship.findUnique({
      where: { id: friendshipId },
    });

    if (!friendship) {
      return res.status(404).json({ error: 'Не найдено' });
    }

    if (friendship.senderId !== userId && friendship.receiverId !== userId) {
      return res.status(403).json({ error: 'Нет доступа' });
    }

    await prisma.friendship.delete({
      where: { id: friendshipId },
    });

    res.json({ message: 'Удалено' });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка удаления' });
  }
};

// Список друзей
const getFriends = async (req, res) => {
  const userId = req.session.userId;

  if (!userId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  try {
    const friendships = await prisma.friendship.findMany({
      where: {
        OR: [
          { senderId: userId, status: 'accepted' },
          { receiverId: userId, status: 'accepted' },
        ],
      },
      include: {
        sender: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
        receiver: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
      },
    });

    // Возвращаем только данные друга, не себя
    const friends = friendships.map((f) => {
      return f.senderId === userId ? f.receiver : f.sender;
    });

    res.json(friends);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения друзей' });
  }
};

// Входящие заявки
const getIncomingRequests = async (req, res) => {
  const userId = req.session.userId;

  if (!userId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  try {
    const requests = await prisma.friendship.findMany({
      where: {
        receiverId: userId,
        status: 'pending',
      },
      include: {
        sender: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
      },
    });

    res.json(requests);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения заявок' });
  }
};

module.exports = {
  searchUsers,
  sendRequest,
  acceptRequest,
  deleteRequest,
  getFriends,
  getIncomingRequests,
};