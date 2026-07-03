const prisma = require('./db/prisma');
const logger = require('./infrastructure/logger');

const onlineUsers = new Map();
const offlineTimers = new Map();
const OFFLINE_DELAY_MS = 5000;

// Фаза 1-6: Состояние сессий
const sessionStates = new Map();  // sessionId -> state
const readyClients = new Map();   // sessionId -> Set(socketId)
const clientRtt = new Map();      // socketId -> rttMs
const syncIntervals = new Map();  // sessionId -> intervalId

let ioInstance;

// ─── Хелперы ──────────────────────────────────────────────────────────────

function getSessionState(sessionId) {
  return sessionStates.get(sessionId) || null;
}

function getCurrentPosition(state) {
  if (!state || state.state !== 'playing') return state?.positionMs || 0;
  return state.positionMs + (Date.now() - state.serverTime);
}

function stopSyncInterval(sessionId) {
  const interval = syncIntervals.get(sessionId);
  if (interval) {
    clearInterval(interval);
    syncIntervals.delete(sessionId);
  }
}

function startSyncInterval(io, sessionId) {
  stopSyncInterval(sessionId);
  const interval = setInterval(() => {
    const state = sessionStates.get(sessionId);
    if (!state || state.state !== 'playing') {
      stopSyncInterval(sessionId);
      return;
    }
    const positionMs = getCurrentPosition(state);
    io.to(sessionId).emit('session_sync', {
      trackId: state.trackId,
      positionMs,
      serverTime: Date.now(),
      state: state.state,
    });
  }, 5000);
  syncIntervals.set(sessionId, interval);
}

function startFromPosition(io, sessionId, trackId, positionMs) {
  const rtts = [];
  const room = ioInstance?.sockets.adapter.rooms.get(sessionId);
  if (room) {
    room.forEach(socketId => {
      const rtt = clientRtt.get(socketId);
      if (rtt) rtts.push(rtt);
    });
  }

  const maxPing = rtts.length > 0 ? Math.max(...rtts) : 300;
  const guard = Math.min(maxPing * 1.5 + 150, 800); // не более 800мс
  const startAt = Date.now() + guard;

  const state = sessionStates.get(sessionId) || {};
  sessionStates.set(sessionId, {
    ...state,
    trackId,
    state: 'playing',
    positionMs,
    serverTime: startAt,
    startAt,
  });

  io.to(sessionId).emit('session_start', {
    trackId,
    startAt,
    positionMs,
    serverTime: Date.now(),
  });

  startSyncInterval(io, sessionId);
}

async function updateOnlineStatus(userId, isOnline) {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!user) return;
    await prisma.user.update({
      where: { id: userId },
      data: { isOnline, lastSeenAt: isOnline ? null : new Date() }
    });
  } catch (err) {
    logger.error({ err, userId }, 'Update online status error');
  }
}

async function getFriendIds(userId) {
  try {
    const friendships = await prisma.friendship.findMany({
      where: { status: 'accepted', OR: [{ senderId: userId }, { receiverId: userId }] },
      select: { senderId: true, receiverId: true }
    });
    return [...new Set(friendships.map(f => f.senderId === userId ? f.receiverId : f.senderId))];
  } catch (err) {
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
    return false;
  }
}

// ─── Setup ────────────────────────────────────────────────────────────────

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
        const userSettings = await prisma.user.findUnique({
          where: { id: userId }, select: { isOnlineHidden: true }
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
      }
    };

    if (socket.handshake?.query?.userId) {
      const qUserId = socket.handshake.query.userId;
      if (typeof qUserId === 'string' && qUserId.trim()) await connectUser(qUserId.trim());
    }

    socket.on('authenticate', async (data) => {
      const token = data?.token || data?.userId || data;
      if (token) await connectUser(token);
    });

    // ─── Фаза 1: Синхронизация часов ───────────────────────────────────────
    socket.on('ping_time', (data) => {
      socket.emit('pong_time', {
        clientTime: data?.clientTime,
        serverTime: Date.now(),
      });
      // Обновляем RTT если клиент прислал
      if (data?.rtt) clientRtt.set(socket.id, data.rtt);
    });

    // ─── Подключение к сессии ───────────────────────────────────────────────
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

      // Фаза 6: Отправляем полное состояние новому участнику
      const state = sessionStates.get(sessionId);
      if (state) {
        const positionMs = getCurrentPosition(state);
        socket.emit('session_state', {
          trackId: state.trackId,
          state: state.state,
          positionMs,
          serverTime: Date.now(),
          startAt: state.startAt,
          durationMs: state.durationMs,
        });
      }
    });

    // ─── Фаза 2: Подготовка трека ───────────────────────────────────────────
    socket.on('session_prepare', async ({ sessionId, trackId, durationMs }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }

      // Сбрасываем готовность
      readyClients.set(sessionId, new Set());
      stopSyncInterval(sessionId);

      sessionStates.set(sessionId, {
        ...(sessionStates.get(sessionId) || {}),
        trackId,
        durationMs,
        state: 'preparing',
        positionMs: 0,
        serverTime: Date.now(),
      });

      // Рассылаем всем включая себя
      io.to(sessionId).emit('session_prepare', { trackId, durationMs });
    });

    // ─── Фаза 2: Клиент готов к воспроизведению ────────────────────────────
    socket.on('client_ready', async ({ sessionId, trackId }) => {
      const uid = socket.data.userId;
      if (!uid) return;

      const ready = readyClients.get(sessionId) || new Set();
      ready.add(socket.id);
      readyClients.set(sessionId, ready);

      // Проверяем все ли в комнате готовы
      const room = io.sockets.adapter.rooms.get(sessionId);
      const roomSize = room ? room.size : 1;
      const READY_TIMEOUT_MS = 5000;

      if (ready.size >= roomSize) {
        // Все готовы — стартуем
        startFromPosition(io, sessionId, trackId, 0);
        readyClients.delete(sessionId);
      } else {
        // Ждём остальных с таймаутом
        if (!sessionStates.get(sessionId)?._readyTimeout) {
          const timeout = setTimeout(() => {
            const state = sessionStates.get(sessionId);
            if (state) state._readyTimeout = null;
            startFromPosition(io, sessionId, trackId, 0);
            readyClients.delete(sessionId);
          }, READY_TIMEOUT_MS);
          const state = sessionStates.get(sessionId) || {};
          state._readyTimeout = timeout;
          sessionStates.set(sessionId, state);
        }
      }
    });

    // ─── Фаза 5: Команды через сервер ──────────────────────────────────────
    socket.on('session_command', async ({ sessionId, action, positionMs: seekPos }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }

      const state = sessionStates.get(sessionId);
      if (!state) return;

      if (action === 'pause') {
        const currentPos = getCurrentPosition(state);
        state.state = 'paused';
        state.positionMs = currentPos;
        state.serverTime = Date.now();
        sessionStates.set(sessionId, state);
        stopSyncInterval(sessionId);
        io.to(sessionId).emit('session_pause', { positionMs: currentPos });

      } else if (action === 'resume') {
  const currentPos = getCurrentPosition(state);
  state.state = 'playing';
  state.positionMs = currentPos;
  state.serverTime = Date.now();
  sessionStates.set(sessionId, state);
  startSyncInterval(io, sessionId);
  // Шлём session_resume, а не session_start
  io.to(sessionId).emit('session_resume', { positionMs: currentPos });

      } else if (action === 'seek') {
        startFromPosition(io, sessionId, state.trackId, seekPos || 0);

      } else if (action === 'next') {
        // Клиент сам передаёт следующий trackId
        const nextTrackId = seekPos; // используем поле как trackId
        if (nextTrackId) {
          io.to(sessionId).emit('session_prepare', { trackId: nextTrackId });
          readyClients.set(sessionId, new Set());
        }
      }
    });

    // ─── Фаза 6: Переподключение ────────────────────────────────────────────
    socket.on('resync', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid) return;

      const state = sessionStates.get(sessionId);
      if (!state) return;

      const positionMs = getCurrentPosition(state);
      socket.emit('session_state', {
        trackId: state.trackId,
        state: state.state,
        positionMs,
        serverTime: Date.now(),
        startAt: state.startAt,
        durationMs: state.durationMs,
      });
    });

    // ─── Устаревшие события (обратная совместимость) ─────────────────────
    socket.on('session_play', async ({ sessionId, spotifyUri, trackIndex, tracks, addedById }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('session_play', { spotifyUri, trackIndex, tracks, addedById: addedById || uid });
    });

    socket.on('play', async ({ sessionId, spotifyUri, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('play', { spotifyUri, position_ms, userId: uid });
    });

    socket.on('pause', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('pause');
    });

    socket.on('seek', async ({ sessionId, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      // Обновляем базовую позицию в состоянии сессии — иначе периодический
      // session_sync (раз в 5с) продолжит считать позицию от точки ДО
      // перемотки и отправит клиентам устаревшее значение, визуально
      // "откатывая" слайдер назад через несколько секунд после перемотки.
      const state = sessionStates.get(sessionId);
      if (state) {
        state.positionMs = position_ms || 0;
        state.serverTime = Date.now();
        sessionStates.set(sessionId, state);
      }

      socket.to(sessionId).emit('seek', { position_ms });
    });

    socket.on('next_track', async ({ sessionId, spotifyUri }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    socket.on('rate_track', async ({ sessionId, trackId, rating }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      try {
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

    socket.on('leave_session', ({ sessionId }) => {
      const uid = socket.data.userId;
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId: uid });
      socket.data.sessionId = null;
    });

    socket.on('disconnect', async () => {
      clientRtt.delete(socket.id);
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
                const settings = await prisma.user.findUnique({
                  where: { id: uid }, select: { isOnlineHidden: true }
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
            }, OFFLINE_DELAY_MS);
            offlineTimers.set(uid, timer);
          }
        }
      }
    });
  });
};

const getIo = () => ioInstance;

const closeSocket = async () => {
  if (ioInstance) {
    syncIntervals.forEach(id => clearInterval(id));
    syncIntervals.clear();
    offlineTimers.forEach(t => clearTimeout(t));
    offlineTimers.clear();
    onlineUsers.clear();
    await new Promise(resolve => ioInstance.close(resolve));
  }
};

module.exports = setupSocket;
module.exports.setupSocket = setupSocket;
module.exports.getIo = getIo;
module.exports.closeSocket = closeSocket;