const prisma = require('./db/prisma');
const logger = require('./infrastructure/logger');

const onlineUsers = new Map();      // userId -> Set(socketId)
const offlineTimers = new Map();    // userId -> Timeout
const OFFLINE_DELAY_MS = 5000;      // 5 секунд grace period
let ioInstance;

async function updateOnlineStatus(userId, isOnline) {
  try {
    const user = await prisma.appUser.findUnique({ where: { id: userId }, select: { id: true } });
    if (!user) {
      logger.warn({ userId }, 'User not found when updating online status');
      return;
    }
    await prisma.appUser.update({
      where: { id: userId },
      data: { isOnline, lastSeenAt: isOnline ? null : new Date() }
    });
    logger.debug({ userId, isOnline }, 'Online status updated');
  } catch (err) {
    logger.error({ err, userId }, 'Update online status error');
  }
}

async function getFriendIds(userId) {
  try {
    const friendships = await prisma.friendship.findMany({
      where: {
        status: 'accepted',
        OR: [{ senderId: userId }, { receiverId: userId }]
      },
      select: { senderId: true, receiverId: true }
    });
    const ids = new Set();
    friendships.forEach(f => {
      ids.add(f.senderId === userId ? f.receiverId : f.senderId);
    });
    return [...ids];
  } catch (err) {
    logger.error({ err, userId }, 'Get friend ids error');
    return [];
  }
}

async function isSessionMember(sessionId, userId) {
  try {
    const member = await prisma.sessionMember.findUnique({
      where: { sessionId_userId: { sessionId, userId } }
    });
    return member && member.status === 'accepted';
  } catch (err) {
    logger.error({ err, sessionId, userId }, 'Check session member error');
    return false;
  }
}

const setupSocket = (io) => {
  ioInstance = io;

  io.on('connection', async (socket) => {
    logger.info({ socketId: socket.id }, 'User connected');
    let userId = null;

    const connectUser = async (incomingUserId) => {
      if (!incomingUserId) return;
      userId = incomingUserId;
      socket.data.userId = userId;
      socket.join(`user:${userId}`);

      if (offlineTimers.has(userId)) {
        clearTimeout(offlineTimers.get(userId));
        offlineTimers.delete(userId);
      }

      const wasOffline = !onlineUsers.has(userId);
      if (!onlineUsers.has(userId)) onlineUsers.set(userId, new Set());
      onlineUsers.get(userId).add(socket.id);

      if (wasOffline) {
        await updateOnlineStatus(userId, true);
        const userSettings = await prisma.appUser.findUnique({
          where: { id: userId },
          select: { isOnlineHidden: true }
        });
        if (!userSettings?.isOnlineHidden) {
          const friendIds = await getFriendIds(userId);
          friendIds.forEach(fid => {
            const friendSockets = onlineUsers.get(fid);
            if (friendSockets) {
              friendSockets.forEach(sid => io.to(sid).emit('friend_online', { userId }));
            }
          });
        }
        logger.info({ userId }, 'User came online');
      }
    };

    // Аутентификация через query или событие
    if (socket.handshake?.query?.userId) {
      const qUserId = socket.handshake.query.userId;
      if (typeof qUserId === 'string' && qUserId.trim()) await connectUser(qUserId.trim());
    }

    socket.on('authenticate', async (data) => {
      const token = data?.token || data?.userId || data;
      if (token) await connectUser(token);
    });

    socket.on('join_session', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid) return socket.emit('error', { message: 'Не авторизован' });
      const member = await prisma.sessionMember.findUnique({
        where: { sessionId_userId: { sessionId, userId: uid } }
      });
      if (!member || member.status !== 'accepted') {
        return socket.emit('error', { message: 'Нет доступа к сессии' });
      }
      socket.join(sessionId);
      socket.data.sessionId = sessionId;
      io.to(sessionId).emit('user_joined', { userId: uid });
      logger.info({ userId: uid, sessionId }, 'User joined session');
    });

    socket.on('play', async ({ sessionId, spotifyUri, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      socket.to(sessionId).emit('play', { spotifyUri, position_ms, userId: uid });
    });

    socket.on('pause', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      socket.to(sessionId).emit('pause');
    });

    socket.on('next_track', async ({ sessionId, spotifyUri }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    socket.on('seek', async ({ sessionId, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      socket.to(sessionId).emit('seek', { position_ms });
    });

    socket.on('rate_track', async ({ sessionId, trackId, rating }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      try {
        await prisma.trackRating.upsert({
          where: { trackId_userId: { trackId, userId: uid } },
          update: { rating },
          create: { trackId, userId: uid, rating }
        });
        io.to(sessionId).emit('track_rated', { trackId, userId: uid, rating });
        logger.debug({ sessionId, trackId, userId: uid, rating }, 'Track rated');
      } catch (error) {
        logger.error({ error, sessionId, trackId, userId: uid }, 'Rate track error');
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    socket.on('leave_session', ({ sessionId }) => {
      const uid = socket.data.userId;
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId: uid });
      socket.data.sessionId = null;
      logger.info({ userId: uid, sessionId }, 'User left session');
    });

    socket.on('disconnect', async () => {
      logger.info({ socketId: socket.id, userId: socket.data.userId }, 'User disconnected');
      const uid = socket.data.userId;
      const sid = socket.data.sessionId;

      if (uid) socket.leave(`user:${uid}`);
      if (sid && uid) io.to(sid).emit('user_left', { userId: uid });

      if (uid) {
        const userSockets = onlineUsers.get(uid);
        if (userSockets) {
          userSockets.delete(socket.id);
          if (userSockets.size === 0) {
            onlineUsers.delete(uid);
            const timer = setTimeout(async () => {
              offlineTimers.delete(uid);
              if (onlineUsers.has(uid)) return;
              await updateOnlineStatus(uid, false);
              try {
                const settings = await prisma.appUser.findUnique({
                  where: { id: uid },
                  select: { isOnlineHidden: true }
                });
                if (!settings?.isOnlineHidden) {
                  const friendIds = await getFriendIds(uid);
                  friendIds.forEach(fid => {
                    const friendSockets = onlineUsers.get(fid);
                    if (friendSockets) {
                      friendSockets.forEach(sid => {
                        io.to(sid).emit('friend_offline', { userId: uid, lastSeenAt: new Date().toISOString() });
                      });
                    }
                  });
                }
              } catch (err) {
                logger.error({ err, userId: uid }, 'Error processing user offline');
              }
              logger.info({ userId: uid }, 'User went offline');
            }, OFFLINE_DELAY_MS);
            offlineTimers.set(uid, timer);
          }
        }
      }
    });
  });

  logger.info('Socket.io server initialized');
};

const getIo = () => {
  if (!ioInstance) logger.warn('Socket.io not initialized yet');
  return ioInstance;
};

const closeSocket = async () => {
  if (ioInstance) {
    for (const timer of offlineTimers.values()) clearTimeout(timer);
    offlineTimers.clear();
    onlineUsers.clear();
    await new Promise(resolve => ioInstance.close(resolve));
    logger.info('Socket.io closed');
  }
};

module.exports = setupSocket;
module.exports.setupSocket = setupSocket;
module.exports.getIo = getIo;
module.exports.closeSocket = closeSocket;