const prisma = require('./db/prisma');
const cookie = require('cookie');

const onlineUsers = new Map(); 

async function updateOnlineStatus(userId, isOnline) {
  try {
    await prisma.appUser.update({
      where: { id: userId },
      data: {
        isOnline,
        lastSeenAt: isOnline ? undefined : new Date()
      }
    });
  } catch (err) {
    console.error('Update online status error:', err.message);
  }
}

async function getFriendIds(userId) {
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
}

const setupSocket = (io) => {
  io.on('connection', async (socket) => {
    console.log('User connected:', socket.id);

    const rawCookie = socket.handshake.headers.cookie;
    let userId = null;
    if (rawCookie) {
      const parsed = cookie.parse(rawCookie);
    }

    socket.on('authenticate', async (data) => {
      const token = data.token;
      if (!token) return;
      userId = token;
      socket.data.userId = userId;

      if (!onlineUsers.has(userId)) {
        onlineUsers.set(userId, new Set());
      }
      onlineUsers.get(userId).add(socket.id);

      await updateOnlineStatus(userId, true);

      const userSettings = await prisma.appUser.findUnique({
        where: { id: userId },
        select: { isOnlineHidden: true }
      });
      if (!userSettings?.isOnlineHidden) {
        const friendIds = await getFriendIds(userId);
        friendIds.forEach(fid => {
          io.to(fid).emit('friend_online', { userId });
          const friendSockets = onlineUsers.get(fid);
          if (friendSockets) {
            friendSockets.forEach(sid => {
              io.to(sid).emit('friend_online', { userId });
            });
          }
        });
      }
    });

    socket.on('join_session', ({ sessionId, userId }) => {
      socket.join(sessionId);
      socket.data.userId = userId;
      socket.data.sessionId = sessionId;
      io.to(sessionId).emit('user_joined', { userId });
      console.log(`User ${userId} joined session ${sessionId}`);
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

    socket.on('rate_track', async ({ sessionId, trackId, rating, userId }) => {
      try {
        const existing = await prisma.trackRating.findFirst({
          where: { trackId, userId },
        });
        if (existing) {
          await prisma.trackRating.update({ where: { id: existing.id }, data: { rating } });
        } else {
          await prisma.trackRating.create({ data: { trackId, userId, rating } });
        }
        io.to(sessionId).emit('track_rated', { trackId, userId, rating });
      } catch (error) {
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    socket.on('leave_session', ({ sessionId, userId }) => {
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId });
    });

    socket.on('disconnect', async () => {
      console.log('User disconnected:', socket.id);
      const uid = socket.data.userId || userId;
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
            await updateOnlineStatus(uid, false);
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
          }
        }
      }
    });
  });
};

module.exports = setupSocket;