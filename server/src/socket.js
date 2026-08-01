const prisma = require('./db/prisma');
const logger = require('./infrastructure/logger');
const { resolveAuthToken } = require('./infrastructure/authTokens');

const onlineUsers = new Map();
const offlineTimers = new Map();
const OFFLINE_DELAY_MS = 5000;

const sessionDropTimers = new Map();
const SESSION_DROP_DELAY_MS = 120000; // 2 мин на переподключение (сон/фон), потом исключаем

// Фаза 1-6: Состояние сессий
const sessionStates = new Map();  // sessionId -> state
const readyClients = new Map();   // sessionId -> Set(socketId)
const clientRtt = new Map();      // socketId -> rttMs
const syncIntervals = new Map();  // sessionId -> intervalId
const autoResyncTimers = new Map(); // sessionId -> timeoutId
const _presenceDebounce = new Map(); // sessionId -> timeoutId

let ioInstance;


function getSessionState(sessionId) {
  return sessionStates.get(sessionId) || null;
}

function getOnlineSessionUsers(sessionId) {
  const ids = new Set();
  const room = ioInstance?.sockets.adapter.rooms.get(sessionId);
  if (room) {
    for (const sockId of room) {
      const s = ioInstance.sockets.sockets.get(sockId);
      if (s?.data?.userId) ids.add(s.data.userId);
    }
  }
  return Array.from(ids);
}

function broadcastSessionPresence(sessionId) {
  if (!ioInstance) return;
  if (_presenceDebounce.has(sessionId)) return; // уже запланировано
  const t = setTimeout(() => {
    _presenceDebounce.delete(sessionId);
    if (!ioInstance) return;
    ioInstance.to(sessionId).emit('session_presence', {
      sessionId,
      onlineUserIds: getOnlineSessionUsers(sessionId),
    });
  }, 800);
  _presenceDebounce.set(sessionId, t);
}

async function transferHostIfNeeded(sessionId, leftUserId) {
  try {
    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      select: { hostId: true, isActive: true },
    });
    if (!session || !session.isActive) return;
    if (session.hostId !== leftUserId) return;

    const onlineIds = getOnlineSessionUsers(sessionId).filter(id => id !== leftUserId);
    if (onlineIds.length === 0) return;

    const candidates = await prisma.sessionMember.findMany({
      where: { sessionId, userId: { in: onlineIds }, status: 'accepted' },
    });
    if (candidates.length === 0) return;
    const newHostId = candidates[0].userId;

    await prisma.session.update({
      where: { id: sessionId },
      data: { hostId: newHostId },
    });

    ioInstance.to(sessionId).emit('host_changed', { sessionId, hostId: newHostId });
  } catch (err) {
    logger.error({ err, sessionId }, 'transferHostIfNeeded error');
  }
}

function getCurrentPosition(state) {
  if (!state || state.state !== 'playing') return state?.positionMs || 0;
  const elapsed = Date.now() - state.serverTime;
  if (elapsed < 0) return state.positionMs;
  return state.positionMs + elapsed;
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
    if (state.startAt && Date.now() < state.startAt + 2000) return;
    const positionMs = getCurrentPosition(state);
    io.to(sessionId).emit('session_sync', {
      trackId: state.trackId,
      positionMs,
      serverTime: Date.now(),
      state: state.state,
    });
  }, 4000);
  syncIntervals.set(sessionId, interval);
}

function startFromPosition(io, sessionId, trackId, positionMs, fastMode = false) {
  const rtts = [];
  const room = ioInstance?.sockets.adapter.rooms.get(sessionId);
  if (room) {
    room.forEach(socketId => {
      const rtt = clientRtt.get(socketId);
      if (rtt) rtts.push(rtt);
    });
  }

  const maxPing = rtts.length > 0 ? Math.max(...rtts) : 300;
  const guard = fastMode
    ? Math.min(maxPing + 400, 1200)
    : Math.min(maxPing * 2 + 600, 2500);
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
  scheduleAutoResync(io, sessionId, trackId, startAt);
}

function cancelAutoResync(sessionId) {
  if (autoResyncTimers.has(sessionId)) {
    const t = autoResyncTimers.get(sessionId);
    clearTimeout(t);
    clearInterval(t); // может быть setInterval; clearTimeout/clearInterval взаимозаменяемы в Node
    autoResyncTimers.delete(sessionId);
  }
}

function scheduleAutoResync(io, sessionId, trackId, startAt) {
  cancelAutoResync(sessionId);
  const firstDelay = Math.max(0, startAt - Date.now()) + 3000;

  function emitReseek() {
    const state = sessionStates.get(sessionId);
    if (!state || state.state !== 'playing' || state.trackId !== trackId) {
      cancelAutoResync(sessionId);
      return;
    }
    const pos = getCurrentPosition(state);
    io.to(sessionId).emit('session_reseek', {
      positionMs: pos,
      serverTime: Date.now(),
      trackId,
    });
  }

  const first = setTimeout(() => {
    emitReseek();
    const interval = setInterval(emitReseek, 12000);
    autoResyncTimers.set(sessionId, interval);
  }, firstDelay);
  autoResyncTimers.set(sessionId, first);
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
    logger.error({ err, userId }, 'getFriendIds error');
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
    logger.error({ err, sessionId, userId }, 'isSessionMember error');
    return false;
  }
}

const setupSocket = (io) => {
  ioInstance = io;

  io.on('connection', async (socket) => {
    let userId;
    try {
      userId = socket.request?.session?.userId;

      if (!userId) {
        const handshakeToken =
          socket.handshake?.auth?.token || socket.handshake?.query?.token;
        if (handshakeToken) {
          userId = await resolveAuthToken(String(handshakeToken));
        }
      }
    } catch (err) {
      logger.error({ err, socketId: socket.id }, 'Error resolving socket identity');
    }

    if (!userId) {
      logger.warn({ socketId: socket.id }, 'Socket connection without a valid session, disconnecting');
      socket.disconnect(true);
      return;
    }

    try {
      logger.info({ socketId: socket.id, userId }, 'User connected');
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
    } catch (err) {
      logger.error({ err, socketId: socket.id, userId }, 'Error during socket connection setup');
      socket.disconnect(true);
      return;
    }

    const on = (event, handler) => {
      socket.on(event, async (...args) => {
        try {
          await handler(...args);
        } catch (err) {
          logger.error({ err, socketId: socket.id, userId: socket.data.userId, event }, 'Unhandled socket event error');
        }
      });
    };

    on('ping_time', (data) => {
      socket.emit('pong_time', {
        clientTime: data?.clientTime,
        serverTime: Date.now(),
      });
      if (data?.rtt) clientRtt.set(socket.id, data.rtt);
    });

    on('join_session', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа к сессии' });
      }
      socket.join(sessionId);
      socket.data.sessionId = sessionId;
      const dropKey = `${sessionId}:${uid}`;
      if (sessionDropTimers.has(dropKey)) {
        clearTimeout(sessionDropTimers.get(dropKey));
        sessionDropTimers.delete(dropKey);
      }
      io.to(sessionId).emit('user_joined', { userId: uid });
      broadcastSessionPresence(sessionId);

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

    on('session_prepare', async ({ sessionId, trackId, durationMs }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }

      readyClients.set(sessionId, new Set());
      stopSyncInterval(sessionId);

      const prevState = sessionStates.get(sessionId);
      if (prevState?._readyTimeout) {
        clearTimeout(prevState._readyTimeout);
      }

      sessionStates.set(sessionId, {
        ...(prevState || {}),
        trackId,
        durationMs,
        state: 'preparing',
        positionMs: 0,
        serverTime: Date.now(),
        _readyTimeout: null,
        pausedDuringPrepare: false,
      });

      io.to(sessionId).emit('session_prepare', { trackId, durationMs });
    });

    function tryStartAfterHandshake(sessionId, trackId) {
      const state = sessionStates.get(sessionId);
      if (!state) return;
      if (state.trackId !== trackId) return;
      if (state.state === 'playing') return;

      if (state.pausedDuringPrepare) {
        state.pausedDuringPrepare = false;
        state.state = 'paused';
        state.positionMs = 0;
        state.serverTime = Date.now();
        sessionStates.set(sessionId, state);
        io.to(sessionId).emit('session_pause', { positionMs: 0 });
        return;
      }
      startFromPosition(io, sessionId, trackId, 0);
    }

    on('client_ready', async ({ sessionId, trackId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      const ready = readyClients.get(sessionId) || new Set();
      ready.add(socket.id);
      readyClients.set(sessionId, ready);

      const room = io.sockets.adapter.rooms.get(sessionId);
      const roomSize = room ? room.size : 1;
      const READY_TIMEOUT_MS = 2500;

      if (ready.size >= roomSize) {
        tryStartAfterHandshake(sessionId, trackId);
        readyClients.delete(sessionId);
      } else {
        if (!sessionStates.get(sessionId)?._readyTimeout) {
          const timeout = setTimeout(() => {
            const state = sessionStates.get(sessionId);
            if (state) state._readyTimeout = null;
            tryStartAfterHandshake(sessionId, trackId);
            readyClients.delete(sessionId);
          }, READY_TIMEOUT_MS);
          const state = sessionStates.get(sessionId) || {};
          state._readyTimeout = timeout;
          sessionStates.set(sessionId, state);
        }
      }
    });

    on('session_command', async ({ sessionId, action, positionMs: seekPos }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }

      const state = sessionStates.get(sessionId);
      if (!state) return;

      cancelAutoResync(sessionId);

      if (action === 'pause') {
        const wasPreparing = state.state === 'preparing';
        const currentPos = getCurrentPosition(state);
        state.state = 'paused';
        state.positionMs = currentPos;
        state.serverTime = Date.now();
        if (wasPreparing) state.pausedDuringPrepare = true;
        sessionStates.set(sessionId, state);
        stopSyncInterval(sessionId);
        io.to(sessionId).emit('session_pause', { positionMs: currentPos });

      } else if (action === 'resume') {
        const currentPos = getCurrentPosition(state);
        state.state = 'playing';
        state.pausedDuringPrepare = false;
        state.positionMs = currentPos;
        state.serverTime = Date.now();
        sessionStates.set(sessionId, state);
        startSyncInterval(io, sessionId);
        io.to(sessionId).emit('session_resume', { positionMs: currentPos });

      } else if (action === 'seek') {
        startFromPosition(io, sessionId, state.trackId, seekPos || 0);

      } else if (action === 'next') {
        const nextTrackId = seekPos; // используем поле как trackId
        if (nextTrackId) {
          io.to(sessionId).emit('session_prepare', { trackId: nextTrackId });
          readyClients.set(sessionId, new Set());
        }
      }
    });

    on('resync', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      socket.join(sessionId);
      socket.data.sessionId = sessionId;
      const dropKey = `${sessionId}:${uid}`;
      if (sessionDropTimers.has(dropKey)) {
        clearTimeout(sessionDropTimers.get(dropKey));
        sessionDropTimers.delete(dropKey);
      }
      broadcastSessionPresence(sessionId);

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

    on('session_play', async ({ sessionId, spotifyUri, trackIndex, tracks, addedById }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('session_play', { spotifyUri, trackIndex, tracks, addedById: addedById || uid });
    });

    on('play', async ({ sessionId, spotifyUri, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('play', { spotifyUri, position_ms, userId: uid });
    });

    on('pause', async ({ sessionId }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('pause');
    });

    on('seek', async ({ sessionId, position_ms }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      const state = sessionStates.get(sessionId);
      if (state) {
        state.positionMs = position_ms || 0;
        state.serverTime = Date.now();
        sessionStates.set(sessionId, state);
      }

      socket.to(sessionId).emit('seek', { position_ms });
    });

    on('next_track', async ({ sessionId, spotifyUri }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    on('session_advance', async ({ sessionId, trackId, durationMs }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      const session = await prisma.session.findUnique({
        where: { id: sessionId }, select: { hostId: true }
      });
      if (!session || session.hostId !== uid) return;

      if (!trackId) return;
      const prev = sessionStates.get(sessionId) || {};
      sessionStates.set(sessionId, { ...prev, durationMs: durationMs || prev.durationMs });
      startFromPosition(io, sessionId, trackId, 0, true);
    });

    on('rate_track', async ({ sessionId, trackId, rating }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;
      try {
        await prisma.trackRating.upsert({
          where: { trackId_userId: { trackId, userId: uid } },
          update: { rating },
          create: { trackId, userId: uid, rating }
        });
        io.to(sessionId).emit('track_rated', { trackId, userId: uid, rating });
      } catch (err) {
        logger.error({ err, sessionId, trackId, userId: uid }, 'Failed to save track rating');
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    on('leave_session', ({ sessionId }) => {
      const uid = socket.data.userId;
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId: uid });
      socket.data.sessionId = null;
      setImmediate(() => {
        broadcastSessionPresence(sessionId);
        if (uid) transferHostIfNeeded(sessionId, uid);
      });
    });

    on('disconnect', async () => {
      clientRtt.delete(socket.id);
      const uid = socket.data.userId;
      const sid = socket.data.sessionId;

      if (uid) socket.leave(`user:${uid}`);
      if (sid && uid) {
        io.to(sid).emit('user_left', { userId: uid });
        setImmediate(() => broadcastSessionPresence(sid));
      }

      if (sid && uid) {
        const dropKey = `${sid}:${uid}`;
        if (sessionDropTimers.has(dropKey)) {
          clearTimeout(sessionDropTimers.get(dropKey));
        }
        const dropTimer = setTimeout(async () => {
          sessionDropTimers.delete(dropKey);
          const room = ioInstance?.sockets.adapter.rooms.get(sid);
          if (room) {
            for (const sockId of room) {
              const s = ioInstance.sockets.sockets.get(sockId);
              if (s?.data?.userId === uid) return;
            }
          }
          io.to(sid).emit('participant_dropped', { userId: uid });
          await transferHostIfNeeded(sid, uid);
        }, SESSION_DROP_DELAY_MS);
        sessionDropTimers.set(dropKey, dropTimer);
      }

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
    sessionDropTimers.forEach(t => clearTimeout(t));
    sessionDropTimers.clear();
    autoResyncTimers.forEach(t => clearTimeout(t));
    autoResyncTimers.clear();
    onlineUsers.clear();
    await new Promise(resolve => ioInstance.close(resolve));
    ioInstance = null;
  }
};

module.exports = setupSocket;
module.exports.setupSocket = setupSocket;
module.exports.getIo = getIo;
module.exports.closeSocket = closeSocket;