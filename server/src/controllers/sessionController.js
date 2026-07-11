const { z } = require('zod');
const prisma = require('../db/prisma');
const { addNotificationJob } = require('../infrastructure/queue');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');
const { getIo } = require('../socket');
const { withLock } = require('../infrastructure/lock');
const asyncHandler = require('../utils/asyncHandler');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

async function notifySessionInvite({ toUserId, sessionId, sessionName, hostId }) {
  const timestamp = Date.now();
  const payload = { type: 'session_invite', toUserId, sessionId, sessionName, hostId, timestamp };
  try {
    await addNotificationJob(payload);
  } catch (e) {
    logger.warn({ err: e, toUserId, sessionId }, 'Queue unavailable, emitting session_invite directly');
    const io = getIo();
    if (io) {
      io.to(`user:${toUserId}`).emit('session_invite', { sessionId, sessionName, hostId, timestamp });
    }
  }
}

async function notifyInviteResponse({ toUserId, userId, accept, sessionId }) {
  const timestamp = Date.now();
  const payload = { type: 'invite_response', toUserId, userId, accept, sessionId, timestamp };
  try {
    await addNotificationJob(payload);
  } catch (e) {
    logger.warn({ err: e, toUserId, sessionId }, 'Queue unavailable, emitting invite_response directly');
    const io = getIo();
    if (io) {
      io.to(`user:${toUserId}`).emit('invite_response', { userId, accept, sessionId, timestamp });
    }
  }
}

const createSessionSchema = z.object({
  name: z.string().optional(),
  friendId: z.string().min(1, 'friendId обязателен'),
});

const sessionIdParamsSchema = z.object({
  sessionId: z.string().min(1),
});

const trackIdParamsSchema = z.object({
  trackId: z.string().min(1),
});

const addTracksBodySchema = z.object({
  tracks: z.array(
    z.object({
      spotifyUri: z.string().min(1, 'spotifyUri обязателен'),
      trackName: z.string().min(1, 'trackName обязателен'),
      artistName: z.string().optional().default(''),
      imageUrl: z.string().optional().nullable(),
      durationMs: z.number().int().positive().optional().nullable(),
    })
  ).min(1, 'Необходимо передать хотя бы один трек'),
});

const rateTrackBodySchema = z.object({
  rating: z.number().int(),
});

const respondToInviteBodySchema = z.object({
  accept: z.boolean(),
});


const createSession = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { name, friendId } = createSessionSchema.parse(req.body);

  if (userId === friendId) {
    return res.status(400).json({ error: 'Нельзя создать сессию с самим собой' });
  }

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
      return res.status(403).json({ error: 'Вы не друзья с этим пользователем' });
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

    // Уведомление
    try {
      await notifySessionInvite({
        toUserId: friendId,
        sessionId: session.id,
        sessionName: session.name,
        hostId: userId,
      });
    } catch (e) {
      logger.error({ err: e }, 'Failed to send session invite notification');
    }

    // Инвалидация кэша
    await incrementVersion();

    res.status(201).json(session);
  });
});

const getMySessions = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:sessions-list:${userId}`;
  const sessions = await getOrSet(cacheKey, 30, async () => {
    return prisma.session.findMany({
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
});

const addTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { sessionId } = sessionIdParamsSchema.parse(req.params);
  const { tracks } = addTracksBodySchema.parse(req.body);

  await withLock(`session:${sessionId}`, 5000, async () => {
    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      include: { members: true },
    });

    if (!session) return res.status(404).json({ error: 'Сессия не найдена' });
    if (!session.isActive) return res.status(400).json({ error: 'Сессия не активна' });

    const isMember = session.members.some(
      (m) => m.userId === userId && m.status === 'accepted'
    );
    if (!isMember) return res.status(403).json({ error: 'Вы не участник этой сессии' });

    // Создаём треки
    const createdTracks = await Promise.all(
      tracks.map((t) =>
        prisma.sessionTrack.create({
          data: {
            sessionId,
            addedById: userId,
            spotifyUri: t.spotifyUri,
            trackName: t.trackName,
            artistName: t.artistName || '',
            imageUrl: t.imageUrl || null,
            durationMs: t.durationMs || null,
          },
          include: { addedBy: { select: { username: true } } },
        })
      )
    );

    // Все треки сессии
    const allTracks = await prisma.sessionTrack.findMany({
      where: { sessionId },
      orderBy: { addedAt: 'asc' },
      include: { addedBy: { select: { username: true } } },
    });

    const autoplayIndex = allTracks.findIndex((t) => t.id === createdTracks[0].id);
    const autoplayUri = createdTracks[0].spotifyUri;

    // Инвалидация кэша
    await incrementVersion();

    // Уведомление
    const tracksPayload = {
      type: 'tracks_added',
      sessionId,
      tracks: createdTracks,
      allTracks,
      autoplayUri,
      autoplayIndex,
      addedById: userId,
      timestamp: Date.now(),
    };

    try {
      await addNotificationJob(tracksPayload);
    } catch (e) {
      logger.warn({ err: e, sessionId }, 'Queue unavailable, emitting tracks-added directly');
      const io = getIo();
      if (io) {
        io.to(sessionId).emit('tracks-added', {
          tracks: createdTracks,
          allTracks,
          autoplayUri,
          autoplayIndex,
          addedById: userId,
        });
        if (autoplayUri != null && autoplayIndex >= 0) {
          io.to(sessionId).emit('session_play', {
            spotifyUri: autoplayUri,
            trackIndex: autoplayIndex,
            addedById: userId,
            tracks: allTracks,
          });
        }
      }
    }

    res.json({ message: `Добавлено ${createdTracks.length} треков`, tracks: createdTracks });
  });
});

const rateTrack = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { trackId } = trackIdParamsSchema.parse(req.params);
  const { rating } = rateTrackBodySchema.parse(req.body);

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

    await incrementVersion();

    try {
      await addNotificationJob({
        type: 'track_rated',
        sessionId: track?.session?.id,
        trackId,
        userId,
        rating,
        timestamp: Date.now(),
      });
    } catch (e) {
      logger.error({ err: e }, 'Failed to enqueue track_rated notification');
    }

    res.json(result);
  });
});

const endSession = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { sessionId } = sessionIdParamsSchema.parse(req.params);

  await withLock(`session:${sessionId}`, 5000, async () => {
    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      include: { members: true },
    });

    if (!session) return res.status(404).json({ error: 'Сессия не найдена' });
    if (!session.isActive) return res.status(400).json({ error: 'Сессия уже завершена' });

    if (session.hostId !== userId) {
      const isMember = session.members.some(
        (m) => m.userId === userId && m.status === 'accepted'
      );
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

    await incrementVersion();

    res.json({ message: 'Сессия завершена', mutualLikes });
  });
});

const respondToInvite = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { sessionId } = sessionIdParamsSchema.parse(req.params);
  const { accept } = respondToInviteBodySchema.parse(req.body);

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
      await notifyInviteResponse({
        toUserId: session.hostId,
        userId,
        accept,
        sessionId,
      });
    } catch (e) {
      logger.error({ err: e }, 'Failed to send invite_response notification');
    }

    await incrementVersion();

    res.json({ status, session });
  });
});

const getMyInvites = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:invites-list:${userId}`;
  const invites = await getOrSet(cacheKey, 30, async () => {
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
    return invitesData.map((i) => i.session);
  });

  res.json(invites);
});

module.exports = { createSession, getMySessions, addTracks, rateTrack, endSession, respondToInvite, getMyInvites };