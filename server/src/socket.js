const prisma = require('./db/prisma');
const cookie = require('cookie');
const logger = require('./infrastructure/logger');
const { invalidateUserDB } = require('./infrastructure/spotify/cache');

const onlineUsers = new Map();
const offlineTimers = new Map(); // userId -> Timeout
const OFFLINE_DELAY_MS = 5000; // 5 секунд "grace period"
let ioInstance;

async function updateOnlineStatus(userId, isOnline) {
  try {
    await prisma.user.update({
      where: { id: userId },
      data: {
        isOnline,
        lastSeenAt: isOnline ? null : new Date()
      }
    });
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
      if (f.senderId === userId) ids.add(f.receiverId);
      else ids.add(f.senderId);
    });
    return [...ids];
  } catch (err) {
    return [];
  }
}

async function isSessionMember(sessionId, userId) {
  const member = await prisma.sessionMember.findUnique({
    where: { sessionId_userId: { sessionId, userId } },
  });
  return member && member.status === 'accepted';
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

      // Отменяем "выход в оффлайн" если был запланирован
      if (offlineTimers.has(userId)) {
        clearTimeout(offlineTimers.get(userId));
        offlineTimers.delete(userId);
      }

      const wasOffline = !onlineUsers.has(userId);

      if (!onlineUsers.has(userId)) {
        onlineUsers.set(userId, new Set());
      }
      onlineUsers.get(userId).add(socket.id);

      // Обновляем БД только если пользователь реально был оффлайн
      if (wasOffline) {
        await updateOnlineStatus(userId, true);

        const userSettings = await prisma.user.findUnique({
          where: { id: userId },
          select: { isOnlineHidden: true }
        });

        if (!userSettings?.isOnlineHidden) {
          const friendIds = await getFriendIds(userId);
          friendIds.forEach(fid => {
            const friendSockets = onlineUsers.get(fid);
            if (friendSockets) {
              friendSockets.forEach(sid => {
                io.to(sid).emit('friend_online', { userId });
              });
            }
          });
        }
      }
    };

    if (socket.handshake?.query?.userId) {
      const handshakeUserId = socket.handshake.query.userId;
      if (typeof handshakeUserId === 'string' && handshakeUserId.trim()) {
        await connectUser(handshakeUserId.trim());
      }
    }

    socket.on('authenticate', async (data) => {
      if (!data) return;
      const token = data.token || data.userId || data;
      if (!token) return;
      await connectUser(token);
    });

    socket.on('join_session', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid) {
        socket.emit('error', { message: 'Не авторизован' });
        return;
      }

      const member = await prisma.sessionMember.findUnique({
        where: { sessionId_userId: { sessionId, userId: uid } },
      });
      if (!member || member.status !== 'accepted') {
        socket.emit('error', { message: 'Нет доступа к сессии' });
        return;
      }

      socket.join(sessionId);
      socket.data.sessionId = sessionId;
      io.to(sessionId).emit('user_joined', { userId: uid });
      logger.info({ userId: uid, sessionId }, 'User joined session');
    });

    socket.on('play', async ({ sessionId, spotifyUri, position_ms }) => {
      if (!await isSessionMember(sessionId, socket.data.userId)) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      socket.to(sessionId).emit('play', { spotifyUri, position_ms });
    });

    socket.on('pause', async ({ sessionId }) => {
      if (!await isSessionMember(sessionId, socket.data.userId)) return socket.emit('error', { message: 'Нет доступа' });
      socket.to(sessionId).emit('pause');
    });

    socket.on('next_track', async ({ sessionId, spotifyUri }) => {
      if (!await isSessionMember(sessionId, socket.data.userId)) return socket.emit('error', { message: 'Нет доступа' });
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    socket.on('seek', async ({ sessionId, position_ms }) => {
      if (!await isSessionMember(sessionId, socket.data.userId)) return socket.emit('error', { message: 'Нет доступа' });
      socket.to(sessionId).emit('seek', { position_ms });
    });

    socket.on('rate_track', async ({ sessionId, trackId, rating }) => {
      const uid = socket.data.userId;
      if (!uid || !await isSessionMember(sessionId, uid)) {
        return socket.emit('error', { message: 'Нет доступа' });
      }
      try {
        await prisma.trackRating.upsert({
          where: { trackId_userId: { trackId, userId: uid } },
          update: { rating },
          create: { trackId, userId: uid, rating },
        });
        io.to(sessionId).emit('track_rated', { trackId, userId: uid, rating });
      } catch (error) {
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    socket.on('leave_session', ({ sessionId }) => {
      const uid = socket.data.userId;
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId: uid });
    });

    socket.on('disconnect', async () => {
      logger.info({ socketId: socket.id }, 'User disconnected');
      const uid = socket.data.userId;
      const sid = socket.data.sessionId;

      if (uid) {
        socket.leave(`user:${uid}`);
      }

      if (sid && uid) {
        io.to(sid).emit('user_left', { userId: uid });
      }

      if (uid) {
        const userSockets = onlineUsers.get(uid);
        if (userSockets) {
          userSockets.delete(socket.id);
          if (userSockets.size === 0) {
            onlineUsers.delete(uid);

            // Не отмечаем offline сразу — даём 5 сек на переподключение
            const timer = setTimeout(async () => {
              offlineTimers.delete(uid);
              // Проверяем что юзер всё ещё оффлайн
              if (onlineUsers.has(uid)) return;

              await updateOnlineStatus(uid, false);
              await invalidateUserDB(uid);

              const settings = await prisma.user.findUnique({
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
            }, OFFLINE_DELAY_MS);

            offlineTimers.set(uid, timer);
          }
        }
      }
    });
  });
};

const getIo = () => ioInstance;

module.exports = setupSocket;
module.exports.getIo = getIo;
