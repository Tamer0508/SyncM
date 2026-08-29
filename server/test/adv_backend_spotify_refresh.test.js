'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

process.env.ENCRYPTION_KEY = 'a'.repeat(64);
process.env.ENCRYPTION_SALT = 'adversarial-test-salt';

const SPOTIFY_USER_ID = '11111111-2222-3333-4444-555555555555';
const STALE_TOKEN = 'OLD_EXPIRED_ACCESS_TOKEN';

const redisPath = require.resolve('../src/infrastructure/redis');
require.cache[redisPath] = {
  id: redisPath,
  filename: redisPath,
  loaded: true,
  exports: {
    acquireLock: async () => null,
    releaseLock: async () => true,
    isRedisAvailable: () => true,
    get: async () => null,
    set: async () => true,
    del: async () => true,
    getWithTTL: async () => null,
    incrementVersion: async () => 1,
    getOrSet: async (_k, _t, _ttl, fn) => fn(),
  },
};

let storedRecord = null;

const prismaPath = require.resolve('../src/db/prisma');
require.cache[prismaPath] = {
  id: prismaPath,
  filename: prismaPath,
  loaded: true,
  exports: {
    spotifyUser: {
      findUnique: async () => storedRecord,
      findFirst: async () => storedRecord,
      update: async () => storedRecord,
    },
  },
};

const {
  refreshAccessToken,
  encryptAccessToken,
} = require('../src/infrastructure/spotify/auth');

test('пока параллельный refresh не закончился, старый токен не выдаётся за новый', async () => {
  const encrypted = await encryptAccessToken(SPOTIFY_USER_ID, STALE_TOKEN);

  storedRecord = { id: SPOTIFY_USER_ID, accessToken: encrypted, refreshToken: null };

  const spotifyUser = { id: SPOTIFY_USER_ID, accessToken: encrypted, refreshToken: null };

  let returned = null;
  let threw = null;
  try {
    returned = await refreshAccessToken(spotifyUser);
  } catch (err) {
    threw = err;
  }

  assert.notEqual(
    returned,
    STALE_TOKEN,
    'refreshAccessToken подождал фиксированные 150 мс, перечитал запись и вернул ' +
      'ТОТ ЖЕ протухший access token, не сверив его с прежним. Вызывающий ' +
      'spotifyRequest уже израсходовал свою единственную попытку обновления, ' +
      'поэтому повторно уходит в Spotify с мёртвым токеном и получает 401. ' +
      'Под нагрузкой (главный экран шлёт несколько запросов к Spotify разом) ' +
      'часть запросов падает без причины. ' +
      (threw ? `Брошено: ${threw.message}` : 'Исключения не было.')
  );
});
