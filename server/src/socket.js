const prisma = require('./db/prisma');
const cookie = require('cookie');

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
    console.error('Update online status error:', err.message);
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

const setupSocket = (io) => {
  ioInstance = io;
  io.on('connection', async (socket) => {
    console.log('User connected:', socket.id);

    let userId = null;

    socket.on('authenticate', async (data) => {
      const token = data.token;
      if (!token) return;
      userId = token;
      socket.data.userId = userId;

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
    });

    socket.on('join_session', ({ sessionId, userId: joinUserId }) => {
      socket.join(sessionId);
      socket.data.userId = joinUserId || userId;
      socket.data.sessionId = sessionId;
      io.to(sessionId).emit('user_joined', { userId: socket.data.userId });
      console.log(`User ${socket.data.userId} joined session ${sessionId}`);
    });

    socket.on('play', ({ sessionId, spotifyUri, position_ms }) => {
      socket.to(sessionId).emit('play', { spotifyUri, position_ms });
    });

    socket.on('pause', ({ sessionId }) => {
      socket.to(sessionId).emit('pause');
    });

    socket.on('next_track', ({ sessionId, spotifyUri }) => {
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    socket.on('seek', ({ sessionId, position_ms }) => {
      socket.to(sessionId).emit('seek', { position_ms });
    });

    socket.on('rate_track', async ({ sessionId, trackId, rating, userId: rUserId }) => {
      try {
        const uid = rUserId || socket.data.userId;
        await prisma.trackRating.upsert({
          where: { trackId_userId: { trackId, userId: uid } },
          update: { rating },
          create: { trackId, userId: uid, rating }
        });
        io.to(sessionId).emit('track_rated', { trackId, userId: uid, rating });
      } catch (error) {
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    socket.on('leave_session', ({ sessionId, userId: lUserId }) => {
      const uid = lUserId || socket.data.userId;
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId: uid });
    });

    socket.on('disconnect', async () => {
      console.log('User disconnected:', socket.id);
      const uid = socket.data.userId;
      const sid = socket.data.sessionId;

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
