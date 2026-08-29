'use strict';

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

const prismaMock = {};
mockModule('../src/db/prisma', prismaMock);
mockModule('../src/infrastructure/redis', {
  getOrSet: async (_ns, _k, _t, fetchFn) => fetchFn(),
  incrementVersion: async () => 1,
  isRedisAvailable: () => false,
  get: async () => null, set: async () => false, del: async () => false,
  acquireLock: async () => null, releaseLock: async () => false, redisClient: null,
});
mockModule('../src/infrastructure/lock', { withLock: async (_r, _t, fn) => fn(), getRedlock: () => null });
mockModule('../src/infrastructure/queue', { addNotificationJob: async () => {}, addPlaylistSyncJob: async () => {} });
mockModule('../src/socket', { getIo: () => null, forgetMembership: () => {} });
mockModule('../src/infrastructure/spotify/artwork', { backfillArtwork: async (_u, rows) => rows });
mockModule('../src/infrastructure/spotify/auth', {
  encryptAccessToken: async (_i, t) => t, encryptRefreshToken: async (_i, t) => t,
  getSpotifyUser: async () => null, spotifyGet: async () => ({}),
});
mockModule('../src/infrastructure/authTokens', {
  issueAuthToken: async () => 'a'.repeat(64), revokeAuthToken: async () => true,
  revokeAllUserTokens: async () => 0, listUserTokens: async () => [],
  revokeUserTokenById: async () => false, resolveAuthToken: async () => null,
  extractBearerToken: () => null, touchAuthToken: async () => {},
});
mockModule('google-auth-library', { OAuth2Client: class {} });
mockModule('multer', Object.assign(() => ({ single: () => (req, _r, cb) => cb(null) }), { diskStorage: (o) => o }));

const playlists = require('../src/controllers/playlistController');
const sessions = require('../src/controllers/sessionController');
const authCtl = require('../src/controllers/authController');

function makeRes() {
  const res = { statusCode: 200, body: undefined, headers: {} };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  res.send = (b) => { res.body = b; return res; };
  res.setHeader = (k, v) => { res.headers[k] = v; };
  return res;
}

async function run(handler, req) {
  const res = makeRes();
  const errors = [];
  await handler(req, res, (e) => errors.push(e));
  await new Promise((r) => setImmediate(r));
  return { res, errors };
}

const notNull = (v, column) =>
  assert.equal(
    typeof v,
    'string',
    `${column} объявлена NOT NULL в prisma/schema.prisma, а контроллер шлёт ${JSON.stringify(v)}`
  );

test('toggleLike без trackName/artistName не отправляет null в NOT NULL колонки', async () => {
  let data = null;
  Object.assign(prismaMock, {
    likedTrack: {
      findUnique: async () => null,
      create: async (args) => { data = args.data; return { id: 'l1' }; },
      delete: async () => ({}),
    },
  });

  const { res } = await run(playlists.toggleLike, {
    userId: 'u1', headers: {}, body: { spotifyUri: 'spotify:track:abc' },
  });

  assert.notEqual(res.statusCode, 400, 'схема приняла запрос — значит он обязан быть исполним');
  assert.ok(data, 'create должен был получить данные');
  notNull(data.trackName, 'LikedTrack.trackName');
  notNull(data.artistName, 'LikedTrack.artistName');
});

test('logPlay без trackName/artistName не отправляет null в NOT NULL колонки', async () => {
  let data = null;
  Object.assign(prismaMock, {
    playHistory: { create: async (args) => { data = args.data; return { id: 'h1' }; } },
  });

  await run(playlists.logPlay, {
    userId: 'u1', headers: {}, body: { spotifyUri: 'spotify:track:abc' },
  });

  assert.ok(data, 'create должен был получить данные');
  notNull(data.trackName, 'PlayHistory.trackName');
  notNull(data.artistName, 'PlayHistory.artistName');
});

test('importPlaylist без name не отправляет null в NOT NULL колонку Playlist.name', async () => {
  let data = null;
  Object.assign(prismaMock, {
    playlist: {
      findFirst: async () => null,
      create: async (args) => { data = args.data; return { id: 'p1', ...args.data }; },
      update: async (args) => ({ id: 'p1', ...args.data }),
    },
  });

  await run(playlists.importPlaylist, {
    userId: 'u1', headers: {}, body: { spotifyPlaylistId: '37i9dQZF1DXcBWIGoYBM5M' },
  });

  assert.ok(data, 'create должен был получить данные');
  notNull(data.name, 'Playlist.name');
});

test('createSession без name не отправляет undefined в NOT NULL колонку Session.name', async () => {
  let data = null;
  Object.assign(prismaMock, {
    friendship: { findFirst: async () => ({ id: 'f1' }) },
    user: {
      findUnique: async () => ({ allowSessionInvites: 'friends', username: 'Friend' }),
      updateMany: async () => ({ count: 2 }),
    },
    session: {
      create: async (args) => {
        data = args.data;
        return { id: 's1', ...args.data, members: [], tracks: [] };
      },
    },
    $transaction: async (fn) => fn(prismaMock),
  });

  const { res } = await run(sessions.createSession, {
    userId: 'host', headers: {}, body: { friendId: 'friend' },
  });

  assert.notEqual(res.statusCode, 400, 'createSessionSchema объявляет name необязательным');
  assert.ok(data, 'session.create должен был получить данные');
  notNull(data.name, 'Session.name');
});

test('getPlayHistory: limit из query не превращается в дробный/отрицательный take', async () => {
  const takes = [];
  Object.assign(prismaMock, {
    playHistory: { findMany: async (args) => { takes.push(args.take); return []; } },
  });

  for (const limit of ['1.3', '-5', '0.5']) {
    await run(authCtl.getPlayHistory, { userId: 'u1', headers: {}, query: { limit } });
  }

  const bad = takes.filter((t) => !Number.isInteger(t) || t <= 0);
  assert.deepEqual(
    bad,
    [],
    'limit не валидируется: Math.min(Number(limit) || 50, 200) пропускает дроби и отрицательные, ' +
      'а take = limit * 4 уходит в Prisma как есть (получено: ' + JSON.stringify(takes) + ')'
  );
});

test('deleteAccount пересчитывает friendsCount у оставшихся друзей', async () => {
  const writes = [];
  Object.assign(prismaMock, {
    user: {
      findUnique: async () => ({ id: 'me', customAvatarUrl: null }),
      delete: async () => ({}),
      update: async (a) => { writes.push(a); return {}; },
      updateMany: async (a) => { writes.push(a); return { count: 0 }; },
    },
    session: { findMany: async () => [] },
    friendship: { findMany: async () => [{ id: 'f1', senderId: 'me', receiverId: 'friend', status: 'accepted' }] },
  });

  const { res } = await run(authCtl.deleteAccount, { userId: 'me', headers: {}, session: null });

  assert.equal(res.statusCode, 200);
  assert.notDeepEqual(
    writes,
    [],
    'user.delete каскадом убирает Friendship, но friendsCount у бывших друзей не трогается — ' +
      'у них навсегда остаётся завышенное число друзей (его отдаёт GET /friends/user/:userId)'
  );
});
