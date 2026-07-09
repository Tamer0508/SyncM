const prisma = require('./db/prisma');
const logger = require('./infrastructure/logger');

const onlineUsers = new Map();
const offlineTimers = new Map();
const OFFLINE_DELAY_MS = 5000;

// Фаза 6.3: таймеры исключения из АКТИВНОЙ СЕССИИ. Отдельно от offlineTimers
// (те — про presence-статус для друзей). Ключ: `${sessionId}:${userId}`.
const sessionDropTimers = new Map();
const SESSION_DROP_DELAY_MS = 120000; // 2 мин на переподключение (сон/фон), потом исключаем

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

// ─── Presence участников сессии ─────────────────────────────────────────────
// Собирает userId всех живых сокетов в комнате сессии — это и есть реально
// подключённые сейчас участники. Не зависит от friends-presence.
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

// Рассылает всем в комнате актуальный список онлайн-участников.
// Дебаунс: при частых reconnect (нестабильная сеть) не спамим комнату чаще
// раза в секунду — иначе клиенты захлёбываются событиями и подлагивают.
const _presenceDebounce = new Map(); // sessionId -> timeoutId
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

// ─── Фаза 7.2: передача управления при уходе хоста ──────────────────────────
// Если хост реально отпал, назначаем новым хостом одного из оставшихся
// онлайн-участников (первого по списку). Обновляем БД и уведомляем комнату,
// чтобы клиенты пересчитали, кто теперь управляет очередью.
async function transferHostIfNeeded(sessionId, leftUserId) {
  try {
    const session = await prisma.session.findUnique({
      where: { id: sessionId },
      select: { hostId: true, isActive: true },
    });
    if (!session || !session.isActive) return;
    // Уходит не хост — передавать нечего.
    if (session.hostId !== leftUserId) return;

    const onlineIds = getOnlineSessionUsers(sessionId).filter(id => id !== leftUserId);
    if (onlineIds.length === 0) return; // никого не осталось — сессия опустела

    // Берём первого онлайн-участника со статусом accepted.
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
  }, 4000);
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
  // guard должен покрыть не только доставку команды (полпинга), но и время
  // загрузки/буферизации трека в Spotify у самого медленного участника.
  // Прежних max(...,800) не хватало при высоком RTT — гость не успевал
  // догрузить трек и стартовал позже хоста. Даём больше запаса.
  const guard = Math.min(maxPing * 2 + 600, 2500);
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
      // Фаза 6.3: вернулся до истечения таймаута — отменяем исключение.
      const dropKey = `${sessionId}:${uid}`;
      if (sessionDropTimers.has(dropKey)) {
        clearTimeout(sessionDropTimers.get(dropKey));
        sessionDropTimers.delete(dropKey);
      }
      io.to(sessionId).emit('user_joined', { userId: uid });
      broadcastSessionPresence(sessionId); // presence: участник онлайн

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

      const prevState = sessionStates.get(sessionId);
      // ВАЖНО: если предыдущий хендшейк (session_prepare → client_ready) не
      // успел собрать всех участников и уже поставил READY_TIMEOUT, этот
      // таймер раньше "переживал" новую подготовку трека — spread ниже
      // копировал ссылку на него в новое состояние, но сам setTimeout не
      // отменялся. Через 5с он стрелял startFromPosition() со СВОИМ, уже
      // устаревшим trackId — это и вызывало повторный запуск трека с нуля
      // ("играет 2-3 секунды и снова на начало").
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

      // Рассылаем всем включая себя
      io.to(sessionId).emit('session_prepare', { trackId, durationMs });
    });

    // Стартуем воспроизведение после хендшейка — если за это время сессию
    // поставили на паузу (см. session_command:pause ниже), не стартуем, а
    // сразу переводим состояние в paused и уведомляем комнату.
    function tryStartAfterHandshake(sessionId, trackId) {
      const state = sessionStates.get(sessionId);
      if (!state) return;

      // Клиент присылал trackId из своего замыкания в момент отправки
      // client_ready — если с тех пор сессия уже успела уйти на подготовку
      // СЛЕДУЮЩЕГО трека (устаревший/запоздавший client_ready), не стартуем
      // по старому trackId поверх актуального состояния.
      if (state.trackId !== trackId) return;

      // ГЛАВНЫЙ ФИКС: если этот трек уже реально играет — не стартуем его
      // заново. roomSize у комнаты Socket.IO может на мгновение "просесть"
      // (кратковременный разрыв соединения / переподключение одного из
      // участников), из-за чего ready.size >= roomSize срабатывает раньше
      // срока, а следом ещё раз — от таймаута или от запоздавшего
      // client_ready второго участника. Раньше каждое такое срабатывание
      // безусловно вызывало startFromPosition() с positionMs=0, из-за чего
      // уже играющий трек резко перезапускался с нуля — по несколько раз
      // подряд ("играет пару секунд и снова на начало"), а локальная позиция
      // на клиентах при этом расходилась с реальным треком в Spotify.
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
      const READY_TIMEOUT_MS = 2500;

      if (ready.size >= roomSize) {
        // Все готовы — стартуем
        tryStartAfterHandshake(sessionId, trackId);
        readyClients.delete(sessionId);
      } else {
        // Ждём остальных с таймаутом
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

    // ─── Фаза 5: Команды через сервер ──────────────────────────────────────
    socket.on('session_command', async ({ sessionId, action, positionMs: seekPos }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) {
        return socket.emit('error', { message: 'Нет доступа' });
      }

      const state = sessionStates.get(sessionId);
      if (!state) return;

      if (action === 'pause') {
        // Если пауза пришла ПОКА идёт хендшейк подготовки следующего трека —
        // одного "state.state = 'paused'" недостаточно: handshake всё равно
        // завершится и tryStartAfterHandshake() запустит воспроизведение,
        // молча "отменяя" паузу пользователя. Помечаем это явным флагом,
        // который проверяется в момент завершения хендшейка.
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

      // После реконнекта это НОВЫЙ сокет — он потерял членство в комнате.
      // Восстанавливаем join (с проверкой прав), иначе участник получит
      // состояние разово, но перестанет получать session_sync/pause/resume.
      const member = await prisma.sessionMember.findUnique({
        where: { sessionId_userId: { sessionId, userId: uid } }
      });
      if (!member || member.status !== 'accepted') return;
      socket.join(sessionId);
      socket.data.sessionId = sessionId;
      // Фаза 6.3: переподключился — отменяем исключение из сессии.
      const dropKey = `${sessionId}:${uid}`;
      if (sessionDropTimers.has(dropKey)) {
        clearTimeout(sessionDropTimers.get(dropKey));
        sessionDropTimers.delete(dropKey);
      }
      broadcastSessionPresence(sessionId); // presence: вернулся онлайн

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

    // ─── Фаза 7.4: быстрый автопереход (без хендшейка) ──────────────────────
    // При естественном завершении трека хост шлёт следующий trackId, и сервер
    // сразу рассылает session_start с коротким guard — минуя ритуал
    // prepare→ready→start. Это убирает 1-2с паузы на стыке треков: остаётся
    // только неизбежная задержка загрузки трека в Spotify (~0.5с).
    // Инициировать может только хост (у него источник очереди).
    socket.on('session_advance', async ({ sessionId, trackId, durationMs }) => {
      const uid = socket.data.userId;
      if (!uid || !(await isSessionMember(sessionId, uid))) return;

      // Проверяем, что это действительно хост сессии.
      const session = await prisma.session.findUnique({
        where: { id: sessionId }, select: { hostId: true }
      });
      if (!session || session.hostId !== uid) return;

      if (!trackId) return;
      // Обновляем длительность в состоянии (для детекта конца у клиентов).
      const prev = sessionStates.get(sessionId) || {};
      sessionStates.set(sessionId, { ...prev, durationMs: durationMs || prev.durationMs });
      // Мгновенный синхронный старт следующего трека с позиции 0.
      startFromPosition(io, sessionId, trackId, 0);
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
      setImmediate(() => {
        broadcastSessionPresence(sessionId);
        // Фаза 7.2: если сессию покинул хост — передаём управление.
        if (uid) transferHostIfNeeded(sessionId, uid);
      });
    });

    socket.on('disconnect', async () => {
      clientRtt.delete(socket.id);
      const uid = socket.data.userId;
      const sid = socket.data.sessionId;

      if (uid) socket.leave(`user:${uid}`);
      if (sid && uid) {
        io.to(sid).emit('user_left', { userId: uid });
        // presence: сокет ещё в комнате в момент события — пересчитываем
        // в следующем тике, когда он уже вышел, чтобы список был актуальным.
        setImmediate(() => broadcastSessionPresence(sid));
      }

      // Фаза 6.3: отпавший участник сессии. Даём время на переподключение;
      // если не вернулся — исключаем из активной сессии и уведомляем комнату.
      // Проверяем, что у пользователя не осталось ДРУГИХ живых сокетов
      // (мультивкладка / несколько устройств) — тогда исключать не нужно.
      if (sid && uid) {
        const dropKey = `${sid}:${uid}`;
        if (sessionDropTimers.has(dropKey)) {
          clearTimeout(sessionDropTimers.get(dropKey));
        }
        const dropTimer = setTimeout(async () => {
          sessionDropTimers.delete(dropKey);
          // Есть ли ещё живые сокеты этого пользователя в этой комнате?
          const room = ioInstance?.sockets.adapter.rooms.get(sid);
          if (room) {
            for (const sockId of room) {
              const s = ioInstance.sockets.sockets.get(sockId);
              if (s?.data?.userId === uid) return; // переподключился — не исключаем
            }
          }
          // Реально отпал — сообщаем комнате. Запись в БД не трогаем (участник
          // остаётся в списке приглашённых и может вернуться), но для активной
          // синхронизации помечаем как выбывшего.
          io.to(sid).emit('participant_dropped', { userId: uid });
          // Фаза 7.2: если отпал хост — передаём управление другому участнику.
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
    onlineUsers.clear();
    await new Promise(resolve => ioInstance.close(resolve));
  }
};

module.exports = setupSocket;
module.exports.setupSocket = setupSocket;
module.exports.getIo = getIo;
module.exports.closeSocket = closeSocket;