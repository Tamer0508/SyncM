'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const db = {
  members: new Map(),
  sessions: new Map(),
  ratings: [],
};

const fakePrisma = {
  sessionMember: {
    async findUnique({ where }) {
      const { sessionId, userId } = where.sessionId_userId;
      const row = db.members.get(`${sessionId}:${userId}`);
      return row ? { status: row.status } : null;
    },
    async findMany({ where }) {
      const out = [];
      for (const [key, row] of db.members) {
        const [sessionId, userId] = key.split(':');
        if (where.status && where.status !== row.status) continue;
        if (typeof where.userId === 'string' && where.userId !== userId) continue;
        if (where.userId && where.userId.in && !where.userId.in.includes(userId)) continue;
        if (where.sessionId && where.sessionId !== sessionId) continue;
        if (where.session && where.session.isActive !== undefined) {
          const s = db.sessions.get(sessionId);
          if (!s || s.isActive !== where.session.isActive) continue;
        }
        out.push({ sessionId, userId, status: row.status });
      }
      return out;
    },
  },
  session: {
    async findUnique({ where }) {
      const s = db.sessions.get(where.id);
      return s ? { ...s } : null;
    },
    async update({ where, data }) {
      const s = db.sessions.get(where.id);
      if (s) Object.assign(s, data);
      return s;
    },
  },
  user: {
    async findUnique() { return { id: 'u', isOnlineHidden: true }; },
    async update() {},
  },
  friendship: { async findMany() { return []; } },
  trackRating: {
    async upsert({ where, update }) {
      db.ratings.push({ ...where.trackId_userId, rating: update.rating });
      return {};
    },
  },
};

function stub(path, exports) {
  require.cache[require.resolve(path)] = {
    id: path, filename: path, loaded: true, children: [], paths: [], exports,
  };
}

const noop = () => {};
stub('../src/db/prisma', fakePrisma);
stub('../src/infrastructure/logger', {
  info: noop, warn: noop, error: noop, debug: noop, fatal: noop, trace: noop,
});
stub('../src/infrastructure/authTokens', { resolveAuthToken: async (token) => token });

const socketModule = require('../src/socket');
const { setupSocket, closeSocket, forgetMembership } = socketModule;

function createHarness() {
  const rooms = new Map();
  const sockets = new Map();
  const roomEmits = [];

  const io = {
    _connection: null,
    sockets: { adapter: { rooms }, sockets },
    on(event, handler) { if (event === 'connection') io._connection = handler; },
    to(room) {
      return {
        emit(event, payload) { roomEmits.push({ room, event, payload, from: 'io' }); },
      };
    },
    close(cb) { if (cb) cb(); },
  };

  return { io, rooms, sockets, roomEmits };
}

async function connect(h, opts) {
  const handlers = new Map();
  const selfEmits = [];
  const socket = {
    id: opts.id,
    data: {},
    request: {},
    handshake: { auth: { token: opts.userId } },
    disconnected: false,
    handlers,
    selfEmits,
    on(event, fn) { handlers.set(event, fn); },
    emit(event, payload) { selfEmits.push({ event, payload }); },
    to(room) {
      return {
        emit(event, payload) {
          h.roomEmits.push({ room, event, payload, from: opts.id });
        },
      };
    },
    join(room) {
      if (!h.rooms.has(room)) h.rooms.set(room, new Set());
      h.rooms.get(room).add(opts.id);
    },
    leave(room) {
      const r = h.rooms.get(room);
      if (r) r.delete(opts.id);
    },
    disconnect() { socket.disconnected = true; },
    async fire(event, payload) {
      const fn = handlers.get(event);
      assert.ok(fn, 'обработчик "' + event + '" не зарегистрирован');
      await fn(payload);
    },
  };
  h.sockets.set(opts.id, socket);
  await h.io._connection(socket);
  return socket;
}

function emitsTo(h, room, event) {
  return h.roomEmits.filter((e) => e.room === room && e.event === event);
}

function reset() {
  db.members.clear();
  db.sessions.clear();
  db.ratings.length = 0;
}

test.afterEach(async () => { await closeSocket(); });

test('S-001: leave_session не проверяет членство — чужак вещает user_left в любую комнату', async () => {
  reset();
  const sid = 's001';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const stranger = await connect(h, { id: 'sock-stranger', userId: 'stranger' });

  await stranger.fire('join_session', { sessionId: sid });
  assert.deepEqual(
    stranger.selfEmits.map((e) => e.event),
    ['error'],
    'join_session чужака обязан быть отклонён — это эталон проверки доступа',
  );
  assert.equal(emitsTo(h, sid, 'user_joined').length, 0);

  h.roomEmits.length = 0;
  await stranger.fire('leave_session', { sessionId: sid });

  assert.equal(
    emitsTo(h, sid, 'user_left').length,
    0,
    'не-член сессии не должен уметь разослать user_left её участникам',
  );
});

test('S-002: завершённая сессия остаётся полностью управляемой по сокету', async () => {
  reset();
  const sid = 's002';
  db.sessions.set(sid, { hostId: 'host', isActive: false });
  db.members.set(sid + ':host', { status: 'accepted' });
  db.members.set(sid + ':guest', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  forgetMembership(sid);

  const guest = await connect(h, { id: 'sock-guest', userId: 'guest' });

  await guest.fire('join_session', { sessionId: sid });
  assert.deepEqual(
    guest.selfEmits.map((e) => e.event),
    ['error'],
    'вход в завершённую сессию обязан быть отклонён',
  );

  await guest.fire('rate_track', { sessionId: sid, trackId: 'trk', rating: 1 });
  assert.equal(db.ratings.length, 0, 'оценка трека в завершённой сессии не должна сохраняться');
});

test('S-003: после завершения сессии сервер вечно вещает session_sync/session_reseek', async (t) => {
  reset();
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });

  const sid = 's003';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const host = await connect(h, { id: 'sock-host', userId: 'host' });

  await host.fire('join_session', { sessionId: sid });
  await host.fire('session_prepare', { sessionId: sid, trackId: 'trk', durationMs: 300000 });
  await host.fire('client_ready', { sessionId: sid, trackId: 'trk' });

  assert.equal(emitsTo(h, sid, 'session_start').length, 1, 'предусловие: трек стартовал');

  db.sessions.get(sid).isActive = false;
  forgetMembership(sid);

  h.roomEmits.length = 0;
  t.mock.timers.tick(60000);

  const sync = emitsTo(h, sid, 'session_sync').length;
  const reseek = emitsTo(h, sid, 'session_reseek').length;
  assert.equal(
    sync + reseek,
    0,
    'завершённая сессия продолжает вещать: session_sync=' + sync + ', session_reseek=' + reseek,
  );
});

test('S-004: seek на паузе принудительно возобновляет воспроизведение у всех', async (t) => {
  reset();
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });

  const sid = 's004';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const host = await connect(h, { id: 'sock-h4', userId: 'host' });

  await host.fire('join_session', { sessionId: sid });
  await host.fire('session_prepare', { sessionId: sid, trackId: 'trk', durationMs: 300000 });
  await host.fire('client_ready', { sessionId: sid, trackId: 'trk' });
  await host.fire('session_command', { sessionId: sid, action: 'pause' });
  assert.equal(emitsTo(h, sid, 'session_pause').length, 1, 'предусловие: сессия на паузе');

  h.roomEmits.length = 0;
  host.selfEmits.length = 0;

  await host.fire('session_command', { sessionId: sid, action: 'seek', positionMs: 30000 });

  assert.equal(
    emitsTo(h, sid, 'session_start').length,
    0,
    'перемотка на паузе не должна рассылать session_start',
  );

  await host.fire('resync', { sessionId: sid });
  const state = host.selfEmits.filter((e) => e.event === 'session_state').pop();
  assert.ok(state, 'resync обязан вернуть состояние');
  assert.equal(state.payload.state, 'paused', 'после перемотки сессия обязана остаться на паузе');
});

test('S-005: client_ready без session_prepare создаёт фантомное состояние сессии', async (t) => {
  reset();
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });

  const sid = 's005';
  db.sessions.set(sid, { hostId: 'a', isActive: true });
  db.members.set(sid + ':a', { status: 'accepted' });
  db.members.set(sid + ':b', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const a = await connect(h, { id: 'sock-a5', userId: 'a' });
  const b = await connect(h, { id: 'sock-b5', userId: 'b' });
  await a.fire('join_session', { sessionId: sid });
  await b.fire('join_session', { sessionId: sid });

  await a.fire('client_ready', { sessionId: sid, trackId: 'stale-track' });

  b.selfEmits.length = 0;
  await b.fire('join_session', { sessionId: sid });

  const state = b.selfEmits.filter((e) => e.event === 'session_state').pop();
  assert.equal(
    state,
    undefined,
    'сессия ничего не играет — слать session_state нечего, но пришло ' +
      JSON.stringify(state && state.payload),
  );
});

test('S-006: join_session эхом возвращает user_joined самому вошедшему и повторяет его на каждом реконнекте', async () => {
  reset();
  const sid = 's006';
  db.sessions.set(sid, { hostId: 'a', isActive: true });
  db.members.set(sid + ':a', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const a = await connect(h, { id: 'sock-a6', userId: 'a' });

  await a.fire('join_session', { sessionId: sid });
  const first = emitsTo(h, sid, 'user_joined');
  assert.equal(first.length, 1);
  assert.notEqual(
    first[0].from,
    'io',
    'user_joined — ретрансляция: её шлют через socket.to (всем, кроме отправителя), как play/pause/seek рядом',
  );

  h.roomEmits.length = 0;
  await a.fire('join_session', { sessionId: sid });
  assert.equal(
    emitsTo(h, sid, 'user_joined').length,
    0,
    'повторный вход уже присутствующего участника не должен заново поднимать всех на перезагрузку сессии',
  );
});

test('REG: полный сценарий хост + участник работает', async () => {
  reset();
  const sid = 'reg1';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });
  db.members.set(sid + ':guest', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);

  const host = await connect(h, { id: 'sock-rh', userId: 'host' });
  const guest = await connect(h, { id: 'sock-rg', userId: 'guest' });

  await host.fire('join_session', { sessionId: sid });
  assert.equal(host.selfEmits.filter((e) => e.event === 'error').length, 0,
      'участник обязан входить в живую сессию');

  h.roomEmits.length = 0;
  await guest.fire('join_session', { sessionId: sid });
  assert.equal(emitsTo(h, sid, 'user_joined').length, 1,
      'о приходе второго участника комнату надо уведомить');

  await host.fire('session_prepare', { sessionId: sid, trackId: 'trk', durationMs: 300000 });
  await host.fire('client_ready', { sessionId: sid, trackId: 'trk' });
  await guest.fire('client_ready', { sessionId: sid, trackId: 'trk' });
  assert.equal(emitsTo(h, sid, 'session_start').length, 1, 'трек обязан стартовать');

  await host.fire('session_command', { sessionId: sid, action: 'pause' });
  assert.equal(emitsTo(h, sid, 'session_pause').length, 1);
  await host.fire('session_command', { sessionId: sid, action: 'resume' });
  assert.equal(emitsTo(h, sid, 'session_resume').length, 1, 'снятие с паузы должно работать');

  h.roomEmits.length = 0;
  await host.fire('session_command', { sessionId: sid, action: 'seek', positionMs: 42000 });
  assert.ok(emitsTo(h, sid, 'session_start').length > 0,
      'перемотка при игре обязана синхронно перезапустить трек у всех');

  await guest.fire('rate_track', { sessionId: sid, trackId: 'trk', rating: 1 });
  assert.equal(db.ratings.length, 1, 'оценка в живой сессии обязана сохраняться');

  h.roomEmits.length = 0;
  await guest.fire('leave_session', { sessionId: sid });
  assert.equal(emitsTo(h, sid, 'user_left').length, 1,
      'о выходе настоящего участника комнату надо уведомить');
});

test('REG: реконнект участника снова уведомляет комнату', async () => {
  reset();
  const sid = 'reg2';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });
  db.members.set(sid + ':guest', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  await connect(h, { id: 'sock-r2h', userId: 'host' });

  const first = await connect(h, { id: 'sock-r2a', userId: 'guest' });
  await first.fire('join_session', { sessionId: sid });

  h.roomEmits.length = 0;
  const second = await connect(h, { id: 'sock-r2b', userId: 'guest' });
  await second.fire('join_session', { sessionId: sid });

  assert.equal(
    emitsTo(h, sid, 'user_joined').length,
    1,
    'после реконнекта участник действительно появился заново — уведомление нужно',
  );
});

test('REG: перемотка на паузе двигает позицию и оставляет паузу', async (t) => {
  reset();
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'] });

  const sid = 'reg3';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });

  const h = createHarness();
  setupSocket(h.io);
  const host = await connect(h, { id: 'sock-r3', userId: 'host' });

  await host.fire('join_session', { sessionId: sid });
  await host.fire('session_prepare', { sessionId: sid, trackId: 'trk', durationMs: 300000 });
  await host.fire('client_ready', { sessionId: sid, trackId: 'trk' });
  await host.fire('session_command', { sessionId: sid, action: 'pause' });

  h.roomEmits.length = 0;
  host.selfEmits.length = 0;
  await host.fire('session_command', { sessionId: sid, action: 'seek', positionMs: 30000 });

  const pause = emitsTo(h, sid, 'session_pause').pop();
  assert.ok(pause, 'новую позицию надо разослать');
  assert.equal(pause.payload.positionMs, 30000, 'позиция обязана дойти до участников');

  await host.fire('resync', { sessionId: sid });
  const state = host.selfEmits.filter((e) => e.event === 'session_state').pop();
  assert.equal(state.payload.positionMs, 30000, 'состояние должно помнить новую позицию');
  assert.equal(state.payload.state, 'paused');
});

test('REG: чужак не может ничего в живой сессии', async () => {
  reset();
  const sid = 'reg4';
  db.sessions.set(sid, { hostId: 'host', isActive: true });
  db.members.set(sid + ':host', { status: 'accepted' });
  db.members.set(sid + ':pending', { status: 'pending' });

  const h = createHarness();
  setupSocket(h.io);
  const host = await connect(h, { id: 'sock-r4h', userId: 'host' });
  await host.fire('join_session', { sessionId: sid });
  await host.fire('session_prepare', { sessionId: sid, trackId: 'trk', durationMs: 300000 });
  await host.fire('client_ready', { sessionId: sid, trackId: 'trk' });

  const pending = await connect(h, { id: 'sock-r4p', userId: 'pending' });
  h.roomEmits.length = 0;

  for (const event of ['join_session', 'leave_session', 'session_prepare', 'client_ready']) {
    await pending.fire(event, { sessionId: sid, trackId: 'trk', durationMs: 1000 });
  }
  await pending.fire('session_command', { sessionId: sid, action: 'pause' });
  await pending.fire('rate_track', { sessionId: sid, trackId: 'trk', rating: 1 });

  assert.equal(emitsTo(h, sid, 'user_joined').length, 0);
  assert.equal(emitsTo(h, sid, 'user_left').length, 0);
  assert.equal(emitsTo(h, sid, 'session_pause').length, 0);
  assert.equal(db.ratings.length, 0, 'оценка от постороннего не должна сохраняться');
});
