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
              { userId, status: 'accepted' },
              { userId: friendId, status: 'pending' },
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

const getMySessions = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const sessions = await prisma.session.findMany({
      where: {
        isActive: true,
        members: { some: { userId } },
      },
      include: {
        members: {
          include: {
            user: { select: { id: true, username: true, spotifyUser: { select: { avatarUrl: true } } } },
          },
        },
        tracks: { include: { addedBy: { select: { username: true } } } },
      },
    });

    res.json(sessions);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения сессий' });
  }
};

const addTracks = async (req, res) => {
  const { sessionId } = req.params;
  const { tracks } = req.body;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const createdTracks = await Promise.all(tracks.map((t) =>
      prisma.sessionTrack.create({
        data: {
          sessionId,
          addedById: userId,
          spotifyUri: t.spotifyUri,
          trackName: t.trackName,
          artistName: t.artistName,
        },
        include: { addedBy: { select: { username: true } } }
      })
    ));

    try {
      const io = getIo();
      if (io) io.to(sessionId).emit('tracks-added', createdTracks);
    } catch (e) {}

    res.json({ message: `Добавлено ${createdTracks.length} треков`, tracks: createdTracks });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка добавления треков' });
  }
};

const rateTrack = async (req, res) => {
  const { trackId } = req.params;
  const { rating } = req.body;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const result = await prisma.trackRating.upsert({
      where: { trackId_userId: { trackId, userId } },
      update: { rating },
      create: { trackId, userId, rating },
    });
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка оценки' });
  }
};

const endSession = async (req, res) => {
  const { sessionId } = req.params;

  try {
    await prisma.session.update({
      where: { id: sessionId },
      data: { isActive: false },
    });

    const tracks = await prisma.sessionTrack.findMany({
      where: { sessionId },
      include: { ratings: true },
    });

    const mutualLikes = tracks.filter(
      (track) =>
        track.ratings.length >= 2 &&
        track.ratings.every((r) => r.rating === 1)
    );

    res.json({ message: 'Сессия завершена', mutualLikes });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка завершения сессии' });
  }
};

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