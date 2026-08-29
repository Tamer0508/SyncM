'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');

delete process.env.REDIS_URL;

function mockModule(relPath, exports) {
  const resolved = require.resolve(relPath);
  require.cache[resolved] = {
    id: resolved, filename: resolved, loaded: true, exports, children: [], paths: [],
  };
  return exports;
}

const store = new Map();
const locks = new Map();

mockModule('../src/infrastructure/redis', {
  isRedisAvailable: () => true,
  get: async (k) => (store.has(k) ? JSON.parse(JSON.stringify(store.get(k))) : null),
  set: async (k, v) => { store.set(k, JSON.parse(JSON.stringify(v))); return true; },
  del: async (k) => store.delete(k),
  acquireLock: async (k) => {
    if (locks.has(k)) return null;
    const token = `t${locks.size + 1}`;
    locks.set(k, token);
    return token;
  },
  releaseLock: async (k, token) => { if (locks.get(k) === token) locks.delete(k); return true; },
});

const idempotencyFactory = require('../src/middleware/idempotency');
const idempotency = idempotencyFactory();

function makeReq({ method = 'POST', url = '/playlists/liked/toggle', body = {}, userId = 'u1', headers = {} } = {}) {
  return { method, originalUrl: url, url, body, userId, headers, log: silentLog };
}

const silentLog = { info() {}, warn() {}, error() {}, debug() {} };

function makeRes() {
  const res = new EventEmitter();
  res.statusCode = 200;
  res.headersSent = false;
  res.status = (c) => { res.statusCode = c; return res; };
  res.getHeaders = () => ({});
  res.setHeader = () => {};
  res.json = (b) => { res.body = b; res.headersSent = true; res.emit('finish'); return res; };
  res.send = (b) => { res.body = b; res.headersSent = true; res.emit('finish'); return res; };
  return res;
}

function pass(req, handler) {
  return new Promise((resolve) => {
    const res = makeRes();
    let reached = false;
    idempotency(req, res, () => { reached = true; handler(req, res); });
    setTimeout(() => resolve({ res, reached }), 400);
  });
}

test.beforeEach(() => { store.clear(); locks.clear(); });

test('POST /playlists/liked/toggle без Idempotency-Key: второй запрос обязан снять лайк', async () => {
  let liked = false;
  const handler = (_req, res) => { liked = !liked; res.status(200).json({ liked }); };

  const first = await pass(makeReq({ body: { spotifyUri: 'spotify:track:abc' } }), handler);
  const second = await pass(makeReq({ body: { spotifyUri: 'spotify:track:abc' } }), handler);

  assert.equal(first.res.body.liked, true);
  assert.equal(
    second.reached,
    true,
    'без заголовка Idempotency-Key ключом становится отпечаток запроса (метод+путь+тело+userId). ' +
      'Два одинаковых тела в пределах 30 секунд неотличимы, поэтому повторный toggle не доходит ' +
      'до контроллера и трек остаётся лайкнутым'
  );
  assert.equal(second.res.body.liked, false, 'ответ отдан из кэша: клиент видит liked:true, лайк не снят');
});

test('чужой ответ по тому же Idempotency-Key не отдаётся другому пользователю', async () => {
  const handler = (req, res) => res.status(200).json({ owner: req.userId, secret: `data-of-${req.userId}` });

  const a = await pass(makeReq({ userId: 'alice', headers: { 'idempotency-key': 'shared-key' } }), handler);
  const b = await pass(makeReq({ userId: 'bob', headers: { 'idempotency-key': 'shared-key' } }), handler);

  assert.equal(a.res.body.owner, 'alice');
  assert.equal(b.res.body.owner, 'bob', 'отпечаток включает userId — подсмотреть чужой ответ нельзя');
});

test('повтор ключа с ДРУГИМ телом не подменяет ответ', async () => {
  const handler = (req, res) => res.status(200).json({ echo: req.body });

  const a = await pass(makeReq({ body: { v: 1 }, headers: { 'idempotency-key': 'k' } }), (q, r) => handler(q, r));
  const b = await pass(makeReq({ body: { v: 2 }, headers: { 'idempotency-key': 'k' } }), (q, r) => handler(q, r));

  assert.deepEqual(a.res.body.echo, { v: 1 });
  assert.deepEqual(b.res.body.echo, { v: 2 });
});
