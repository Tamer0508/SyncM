const prisma = require('../db/prisma');
const { getIo } = require('../socket');

const createSession = async (req, res) => {
  const { name, friendId } = req.body;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  if (!friendId) return res.status(400).json({ error: 'friendId обязателен' });

  try {
    const session = await prisma.$transaction(async (tx) => {
      const newSession = await tx.session.create({
        data: {
          name,
          hostId: userId,
          members: {
            create: [
              { userId, status: 'accepted' },       // хост сразу принят
              { userId: friendId, status: 'pending' }, // друг ожидает
            ],
          },
        },
        include: {
          members: {
            include: {
              user: {
                select: { id: true, username: true, spotifyUser: { select: { avatarUrl: true } } },
              },
            },
          },
        },
      });

      await tx.user.updateMany({
        where: { id: { in: [userId, friendId] } },
        data: { sessionsCount: { increment: 1 } }
      });

      return newSession;
    });

    // Уведомляем друга через сокет
    try {
      const io = getIo();
      if (io) {
        io.to(friendId).emit('session_invite', {
          sessionId: session.id,
          sessionName: session.name,
          hostId: userId,
        });
      }
    } catch (e) {}

    res.json(session);
  } catch (error) {
    console.error('Create session error:', error);
    res.status(500).json({ error: 'Ошибка создания сессии', details: error.message });
  }
};

// Добавь новые функции:
const respondToInvite = async (req, res) => {
  const { sessionId } = req.params;
  const { accept } = req.body;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const status = accept ? 'accepted' : 'declined';
    await prisma.sessionMember.updateMany({
      where: { sessionId, userId },
      data: { status },
    });

    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      include: {
        members: {
          include: {
            user: { select: { id: true, username: true, spotifyUser: { select: { avatarUrl: true } } } },
          },
        },
        tracks: true,
      },
    });

    // Уведомляем хоста
    try {
      const io = getIo();
      if (io) {
        io.to(session.hostId).emit('invite_response', { userId, accept, sessionId });
      }
    } catch (e) {}

    res.json({ status, session });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка ответа на приглашение' });
  }
};

const getMyInvites = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const invites = await prisma.sessionMember.findMany({
      where: { userId, status: 'pending' },
      include: {
        session: {
          include: {
            members: {
              include: {
                user: { select: { id: true, username: true, spotifyUser: { select: { avatarUrl: true } } } },
              },
            },
          },
        },
      },
    });
    res.json(invites.map(i => i.session));
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения приглашений' });
  }
};

module.exports = { createSession, getMySessions, addTracks, rateTrack, endSession, respondToInvite, getMyInvites };
