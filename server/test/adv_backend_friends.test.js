'use strict';

// Враждебные тесты friendsController: счётчики, поиск, несуществующие цели.
// БД нет — Prisma и Redis подменяются в require.cache ДО загрузки контроллера.

const test = require('node:test');
const assert = require('node:assert/strict');

delete process.env.REDIS_URL;

function mockModule(relPath, exports) {
  const resolved = require.resolve(relPath);
  require.cache[resolved] = {
    id: resolved, filename: resolved, loaded: true, exports, children: [], paths: [],
  };
  return exports;
}

// ---- заглушки инфраструктуры -------------------------------------------
const prismaMock = {};
mockModule('../src/db/prisma', prismaMock);
mockModule('../src/infrastructure/redis', {
  getOrSet: async (_ns, _key, _ttl, fetchFn) => fetchFn(),
  incrementVersion: async () => 1,
  isRedisAvailable: () => false,
  get: async () => null,
  set: async () => false,
  del: async () => false,
  acquireLock: async () => null,
  releaseLock: async () => false,
  redisClient: null,
});
mockModule('../src/infrastructure/lock', {
  withLock: async (_res, _ttl, fn) => fn(),
  getRedlock: () => null,
});
mockModule('../src/infrastructure/queue', {
  addNotificationJob: async () => {},
  addPlaylistSyncJob: async () => {},
});
mockModule('../src/socket', { getIo: () => null, forgetMembership: () => {} });

const friends = require('../src/controllers/friendsController');

function makeRes() {
  const res = { statusCode: 200, body: undefined, finished: false };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; res.finished = true; return res; };
  return res;
}

const run = async (handler, req) => {
  const res = makeRes();
  const errors = [];
  await handler(req, res, (err) => errors.push(err));
  await new Promise((r) => setImmediate(r));
  return { res, errors };
};

// ---------------------------------------------------------------------------
test('blockUser: блокировка автора ВИСЯЩЕЙ заявки не должна уменьшать friendsCount', async () => {
  const decrements = [];

  Object.assign(prismaMock, {
    user: {
      findUnique: async () => ({ id: 'victim' }),
      update: async () => ({}),
      updateMany: async (args) => { decrements.push(args); return { count: 2 }; },
    },
    block: { upsert: async () => ({}) },
    friendship: {
      // В базе одна СТРОКА ЗАЯВКИ (status = pending), дружбы нет.
      deleteMany: async () => ({ count: 1 }),
      count: async () => 0,
    },
    $transaction: async (fn) => fn(prismaMock),
  });

  const { res } = await run(friends.blockUser, {
    userId: 'blocker',
    params: { userId: 'victim' },
    headers: {},
  });

  assert.equal(res.statusCode, 200);
  assert.deepEqual(
    decrements,
    [],
    'deleteMany удаляет заявки ЛЮБОГО статуса, а friendsCount уменьшается по одному лишь count>0 — ' +
      'блокировка автора pending-заявки списывает по одному другу у обоих, хотя друзьями они не были'
  );
});

// ---------------------------------------------------------------------------
test('searchUsers: имя из 8 символов алфавита Crockford всё ещё ищется по username', async () => {
  let capturedWhere = null;

  Object.assign(prismaMock, {
    user: {
      findMany: async (args) => {
        capturedWhere = args.where;
        return [];
      },
    },
  });

  // "Coldplay" -> normalizePublicId -> "C01DP1AY": ровно 8 символов алфавита.
  await run(friends.searchUsers, {
    userId: 'me',
    query: { query: 'Coldplay' },
    headers: {},
  });

  assert.ok(capturedWhere, 'запрос к базе должен был состояться');
  assert.ok(
    capturedWhere.username || (capturedWhere.OR || []).some((c) => c.username),
    'запрос ушёл только по publicId: любое 8-символьное имя (Coldplay, Beatles1, ...) ' +
      'нормализуется в publicId и перестаёт находиться по имени'
  );
});

// ---------------------------------------------------------------------------
test('sendRequest: заявка несуществующему получателю — 404, а не падение по FK', async () => {
  const fkError = Object.assign(new Error('Foreign key constraint failed'), { code: 'P2003' });

  Object.assign(prismaMock, {
    user: { findUnique: async () => null },
    block: { findFirst: async () => null },
    friendship: {
      findFirst: async () => null,
      create: async () => { throw fkError; },
    },
  });

  const { res, errors } = await run(friends.sendRequest, {
    userId: 'me',
    body: { receiverId: 'no-such-user' },
    headers: {},
  });

  assert.equal(
    errors.length,
    0,
    'существование получателя не проверяется — ошибка внешнего ключа уходит в общий ' +
      'обработчик, где нет ветки P2003, и клиент получает 500 вместо 404'
  );
  assert.equal(res.statusCode, 404);
});
