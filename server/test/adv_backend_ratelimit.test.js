'use strict';

// Adversarial-тесты ограничителя частоты и разбора числовых параметров.
//
// Тесты НАМЕРЕННО падают на текущей реализации.
//
// Атакуемый код: server/src/infrastructure/rateLimiter.js
//                server/src/controllers/authController.js (getPlayHistory)

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

// ---- подмена Redis до загрузки ограничителя -------------------------------

const redisPath = require.resolve('../src/infrastructure/redis');
const usedKeys = [];

require.cache[redisPath] = {
  id: redisPath,
  filename: redisPath,
  loaded: true,
  exports: {
    isRedisAvailable: () => true,
    redisClient: {
      // Возвращаем [current, ttl] так же, как боевой Lua-скрипт.
      eval: async (_script, _numKeys, key, windowSeconds) => {
        usedKeys.push(key);
        const current = usedKeys.filter((k) => k === key).length;
        return [current, Number(windowSeconds)];
      },
    },
    get: async () => null,
    set: async () => true,
    del: async () => true,
    getWithTTL: async () => null,
    incrementVersion: async () => 1,
    getOrSet: async (_k, _t, _ttl, fn) => fn(),
  },
};

const { rateLimitMiddleware } = require('../src/infrastructure/rateLimiter');

/// Минимальный req: ограничитель смотрит на userId, метод, точку монтирования
/// роутера (`baseUrl`) и путь внутри него (`route.path`) — ровно то, что
/// Express проставляет реальному запросу.
function fakeReq({ method, routePath, baseUrl = '', userId = 'user-1' }) {
  return {
    method,
    userId,
    baseUrl,
    route: { path: routePath },
    path: routePath,
    headers: {},
    socket: {},
  };
}

function fakeRes() {
  return {
    statusCode: 200,
    headers: {},
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

function run(middleware, req) {
  return new Promise((resolve) => {
    const res = fakeRes();
    middleware(req, res, () => resolve({ res, passed: true }));
    setTimeout(() => resolve({ res, passed: false }), 50);
  });
}

test('лимиты разных ресурсов не делят один счётчик', async () => {
  usedKeys.length = 0;

  // Три РАЗНЫХ эндпоинта, у каждого свой router, но у всех route.path === '/':
  //   GET /friends   (routes/friends.js)
  //   GET /playlists (routes/playlists.js)
  //   GET /sessions  (routes/sessions.js)
  await run(rateLimitMiddleware(15, 60),
      fakeReq({ method: 'GET', baseUrl: '/friends', routePath: '/' }));
  await run(rateLimitMiddleware(15, 60),
      fakeReq({ method: 'GET', baseUrl: '/playlists', routePath: '/' }));
  await run(rateLimitMiddleware(20, 60),
      fakeReq({ method: 'GET', baseUrl: '/sessions', routePath: '/' }));

  const distinct = new Set(usedKeys);

  assert.equal(
    distinct.size,
    3,
    `Список друзей, список плейлистов и список сессий пишутся в один ключ ` +
      `${[...distinct].join(', ')}. Ключ собирается из req.route.path, который ` +
      `относителен роутеру и не включает точку монтирования, поэтому '/' у трёх ` +
      `разных ресурсов совпадает. Открытие главного экрана тратит общий бюджет ` +
      `втрое быстрее, и человек ловит 429 на обычной работе.`
  );
});

test('лимит одного ресурса не расходуется запросами к другому', async () => {
  usedKeys.length = 0;

  const friends = rateLimitMiddleware(15, 60);
  const playlists = rateLimitMiddleware(15, 60);

  // 15 законных обращений к списку друзей — ровно в пределах лимита.
  for (let i = 0; i < 15; i++) {
    await run(friends, fakeReq({ method: 'GET', baseUrl: '/friends', routePath: '/' }));
  }

  // Первое же обращение к списку плейлистов — оно первое, лимит не тронут.
  const { res } = await run(
    playlists,
    fakeReq({ method: 'GET', baseUrl: '/playlists', routePath: '/' }),
  );

  assert.notEqual(
    res.statusCode,
    429,
    'Первый за окно запрос списка плейлистов отбит как «слишком много запросов», ' +
      'потому что бюджет уже израсходован обращениями к списку друзей.'
  );
});
