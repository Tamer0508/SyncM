const prisma = require('../db/prisma');
const { getIo } = require('../socket');
const { getOrSet, invalidateUserDB } = require('../infrastructure/spotify/cache');

const createSession = async (req, res) => {
  const { name, friendId } = req.body;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  if (!friendId) return res.status(400).json({ error: 'friendId обязателен' });
  if (userId === friendId) return res.status(400).json({ error: 'Нельзя создать сессию с самим собой' });

  try {
    const { withLock } = require('../infrastructure/lock');

    await withLock(`session:create:${userId}`, 5000, async () => {
      const friendship = await prisma.friendship.findFirst({
        where: {
          status: 'accepted',
          OR: [
            { senderId: userId, receiverId: friendId },
            { senderId: friendId, receiverId: userId },
          ],
        },
      });
      if (!friendship) {
        res.status(403).json({ error: 'Вы не друзья с этим пользователем' });
        return;
      }

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
            tracks: true,
          },
        });

        await tx.user.updateMany({
          where: { id: { in: [userId, friendId] } },
          data: { sessionsCount: { increment: 1 } },
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

      await invalidateUserDB(userId);
      await invalidateUserDB(friendId);

      res.status(201).json(session);
    });
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

  const cacheKey = `db:sessions-list:${userId}`;

  try {
    const sessions = await getOrSet(cacheKey, null, async () => {
      return await prisma.session.findMany({
        where: {
          isActive: true,
          members: { some: { userId, status: 'accepted' } },
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
    });
    res.json(sessions);
  } catch (error) {
    console.error('Get sessions error:', error);
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
  if (!Array.isArray(tracks) || tracks.length === 0) {
    return res.status(400).json({ error: 'Необходимо передать массив треков' });
  }

  try {
    const { withLock } = require('../infrastructure/lock');

    // Lock per session to avoid race conditions when adding tracks
    await withLock(`session:${sessionId}`, 5000, async () => {
      const session = await prisma.session.findUnique({
        where: { id: sessionId },
        include: { members: true },
      });
    if (!session) return res.status(404).json({ error: 'Сессия не найдена' });
    if (!session.isActive) return res.status(400).json({ error: 'Сессия не активна' });

    const isMember = session.members.some(
      m => m.userId === userId && m.status === 'accepted'
    );
    if (!isMember) return res.status(403).json({ error: 'Вы не участник этой сессии' });

      const createdTracks = await Promise.all(tracks.map((t) =>
        prisma.sessionTrack.create({
          data: {
            sessionId,
            addedById: userId,
            spotifyUri: t.spotifyUri,
            trackName: t.trackName,
            artistName: t.artistName || '',
            durationMs: t.durationMs || null,
          },
          include: { addedBy: { select: { username: true } } },
        })
      ));

      const userIds = session.members.map(m => m.userId);
      await Promise.all(userIds.map(uid => invalidateUserDB(uid)));

      try {
        const io = getIo();
        if (io) io.to(sessionId).emit('tracks-added', createdTracks);
      } catch (e) {}

      res.json({ message: `Добавлено ${createdTracks.length} треков`, tracks: createdTracks });
    });
  } catch (error) {
    console.error('Add tracks error:', error);
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
    const { withLock } = require('../infrastructure/lock');

    // Lock per track to avoid concurrent upserts from race conditions
    await withLock(`track:rating:${trackId}`, 3000, async () => {
      const result = await prisma.trackRating.upsert({
        where: { trackId_userId: { trackId, userId } },
        update: { rating },
        create: { trackId, userId, rating },
      });

      const track = await prisma.sessionTrack.findUnique({
        where: { id: trackId },
        include: { session: { include: { members: true } } },
      });
      if (track?.session) {
        const userIds = track.session.members.map(m => m.userId);
        await Promise.all(userIds.map(uid => invalidateUserDB(uid)));
      }

      res.json(result);
    });
  } catch (error) {
    console.error('Rate track error:', error);
    res.status(500).json({ error: 'Ошибка оценки' });
  }
};

const endSession = async (req, res) => {
  const { sessionId } = req.params;
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const { withLock } = require('../infrastructure/lock');

    // Lock session while ending it to avoid concurrent end operations
    await withLock(`session:${sessionId}`, 5000, async () => {
      const session = await prisma.session.findUnique({
        where: { id: sessionId },
        include: { members: true },
      });

      if (!session) return res.status(404).json({ error: 'Сессия не найдена' });
      if (!session.isActive) return res.status(400).json({ error: 'Сессия уже завершена' });
      if (session.hostId !== userId) {
        const isMember = session.members.some(m => m.userId === userId && m.status === 'accepted');
        if (!isMember) return res.status(403).json({ error: 'Вы не участник этой сессии' });
        return res.status(403).json({ error: 'Только создатель сессии может её завершить' });
      }

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

      const userIds = session.members.map(m => m.userId);
      await Promise.all(userIds.map(uid => invalidateUserDB(uid)));

      res.json({ message: 'Сессия завершена', mutualLikes });
    });
  } catch (error) {
    console.error('End session error:', error);
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
    const { withLock } = require('../infrastructure/lock');

    // Lock session member row to avoid concurrent accept/decline races
    await withLock(`session:${sessionId}:member:${userId}`, 5000, async () => {
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

      await invalidateUserDB(userId);
      if (accept) {
        await invalidateUserDB(session.hostId);
      }
      res.json({ status, session });
    });
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

  const cacheKey = `db:invites-list:${userId}`;

  try {
    const invites = await getOrSet(cacheKey, null, async () => {
      const invitesData = await prisma.sessionMember.findMany({
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
      return invitesData.map(i => i.session);
    });
    res.json(invites);
  } catch (error) {
    console.error('Get invites error:', error);
    res.status(500).json({ error: 'Ошибка получения приглашений' });
  }
};

module.exports = { createSession, getMySessions, addTracks, rateTrack, endSession, respondToInvite, getMyInvites };