'use strict';

// Атака: удаление ЧУЖИХ файлов из uploads/ через подставленный старый URL.
// Ни safeDeleteOldAvatar, ни safeDeleteCover не проверяют, кому принадлежит
// файл, а сам «старый URL» полностью контролируется атакующим (PATCH профиля
// / PATCH плейлиста принимают любой http(s)-адрес).

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fsp = require('node:fs/promises');

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
  getOrSet: async (_ns, _key, _ttl, fetchFn) => fetchFn(),
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
  encryptAccessToken: async (_id, t) => `enc:${t}`,
  encryptRefreshToken: async (_id, t) => `enc:${t}`,
  getSpotifyUser: async () => null,
  spotifyGet: async () => ({}),
});
mockModule('../src/infrastructure/authTokens', {
  issueAuthToken: async () => 'a'.repeat(64),
  revokeAuthToken: async () => true,
  revokeAllUserTokens: async () => 0,
  listUserTokens: async () => [],
  revokeUserTokenById: async () => false,
  resolveAuthToken: async () => null,
  extractBearerToken: () => null,
  touchAuthToken: async () => {},
});
mockModule('google-auth-library', { OAuth2Client: class { async verifyIdToken() { return { getPayload: () => ({}) }; } } });

// Управляемая заглушка multer: сама «принимает» файл, ничего не пишет на диск.
let nextUploadedFile = null;
mockModule('multer', Object.assign(
  () => ({ single: () => (req, _res, cb) => { req.file = nextUploadedFile; cb(null); } }),
  { diskStorage: (opts) => opts }
));

const auth = require('../src/controllers/authController');
const playlists = require('../src/controllers/playlistController');

const AVATARS_DIR = path.resolve(__dirname, '../src/../uploads/avatars');
const COVERS_DIR = path.resolve(__dirname, '../src/../uploads/covers');

function makeRes() {
  const res = { statusCode: 200, body: undefined };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  res.send = (b) => { res.body = b; return res; };
  res.get = () => 'syncm.example';
  return res;
}

// Перехват fsp.unlink: контроллеры держат ссылку на сам модуль fs/promises,
// поэтому подмена свойства видна им сразу. Возвращаем оригинал в finally.
async function captureUnlinks(fn) {
  const calls = [];
  const original = fsp.unlink;
  fsp.unlink = async (p) => { calls.push(String(p)); };
  try {
    await fn();
  } finally {
    fsp.unlink = original;
  }
  return calls;
}

// ---------------------------------------------------------------------------
test('uploadAvatar не удаляет файл аватара другого пользователя', async () => {
  const victimFile = 'victim-user-id_1700000000000_deadbeefcafe.png';

  // Атакующий заранее выставил себе customAvatarUrl = адрес аватарки жертвы
  // (PATCH /auth/profile принимает любой http(s) URL — своего файла не требует).
  Object.assign(prismaMock, {
    user: {
      findUnique: async () => ({ customAvatarUrl: `https://syncm.example/uploads/avatars/${victimFile}` }),
      update: async () => ({ id: 'attacker', username: 'a', customAvatarUrl: 'x', spotifyUser: null }),
    },
  });

  nextUploadedFile = {
    filename: 'attacker_1700000001000_aabbccddeeff.png',
    path: path.join(AVATARS_DIR, 'attacker_1700000001000_aabbccddeeff.png'),
    originalname: 'me.png',
    mimetype: 'image/png',
  };

  const calls = await captureUnlinks(async () => {
    const res = makeRes();
    auth.uploadAvatar({ userId: 'attacker', headers: {}, body: {}, params: {}, get: () => 'syncm.example' }, res);
    await new Promise((r) => setTimeout(r, 30));
  });

  assert.deepEqual(
    calls,
    [],
    `safeDeleteOldAvatar берёт basename из ЛЮБОГО сохранённого URL и удаляет ` +
      `uploads/avatars/<имя> без проверки владельца — файл жертвы стирается (${victimFile})`
  );
});

// ---------------------------------------------------------------------------
test('updatePlaylist не удаляет файл обложки, который ему не принадлежит', async () => {
  const victimFile = 'victim-user-id_1700000000000_0123456789ab.jpg';

  Object.assign(prismaMock, {
    playlist: {
      findUnique: async () => ({
        id: 'p1',
        userId: 'attacker',
        isCustom: true,
        // Атакующий подставил сюда адрес чужой обложки предыдущим PATCH'ем.
        imageUrl: `https://syncm.example/uploads/covers/${victimFile}`,
      }),
      update: async () => ({ id: 'p1', name: 'n', imageUrl: null, isCustom: true, _count: { playlistTracks: 0 } }),
    },
  });

  const calls = await captureUnlinks(async () => {
    const res = makeRes();
    await playlists.updatePlaylist(
      { userId: 'attacker', params: { playlistId: 'p1' }, body: { imageUrl: null }, headers: {} },
      res,
      () => {}
    );
    await new Promise((r) => setTimeout(r, 20));
  });

  assert.deepEqual(
    calls.map((p) => path.basename(p)),
    [],
    `safeDeleteCover проверяет только префикс пути, но не владельца файла: ` +
      `любой пользователь стирает произвольный файл из uploads/covers (${victimFile})`
  );
  void COVERS_DIR;
});

// ---------------------------------------------------------------------------
test('uploadAvatar: старый URL с чужого домена не даёт удалять файлы из uploads/avatars', async () => {
  const victimFile = 'victim-user-id_1700000000000_deadbeefcafe.png';

  Object.assign(prismaMock, {
    user: {
      // Ни префикса /uploads/avatars/, ни своего домена — только basename.
      findUnique: async () => ({ customAvatarUrl: `https://evil.example/x/y/${victimFile}` }),
      update: async () => ({ id: 'attacker', username: 'a', customAvatarUrl: 'x', spotifyUser: null }),
    },
  });

  nextUploadedFile = {
    filename: 'attacker_1700000002000_112233445566.png',
    path: path.join(AVATARS_DIR, 'attacker_1700000002000_112233445566.png'),
    originalname: 'me.png',
    mimetype: 'image/png',
  };

  const calls = await captureUnlinks(async () => {
    const res = makeRes();
    auth.uploadAvatar({ userId: 'attacker', headers: {}, body: {}, params: {}, get: () => 'syncm.example' }, res);
    await new Promise((r) => setTimeout(r, 30));
  });

  assert.deepEqual(
    calls,
    [],
    'в safeDeleteOldAvatar нет проверки pathname.startsWith("/uploads/avatars/") — ' +
      'достаточно любого http(s) URL, у которого совпадает имя файла'
  );
});
