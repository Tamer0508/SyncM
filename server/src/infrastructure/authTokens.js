const crypto = require('crypto');
const { set, get, del, getWithTTL, isRedisAvailable, redisClient } = require('./redis');
const { deviceIdFor } = require('../utils/device');
const logger = require('./logger');


const TOKEN_BYTES = 32;
const TOKEN_REGEX = /^[a-f0-9]{64}$/;
const KEY_PREFIX = 'authtoken:';

const USER_TOKENS_PREFIX = 'authtokens:user:';

const TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60;

function keyFor(token) {
  return `${KEY_PREFIX}${token}`;
}

async function issueAuthToken(userId, { ttlSeconds = TOKEN_TTL_SECONDS, device = null } = {}) {
  if (!userId) throw new Error('issueAuthToken: userId обязателен');

  if (!isRedisAvailable()) {
    throw new Error('Невозможно выдать токен аутентификации: Redis недоступен');
  }

  const now = Date.now();
  const token = crypto.randomBytes(TOKEN_BYTES).toString('hex');
  const stored = await set(
    keyFor(token),
    { userId, issuedAt: now, lastSeenAt: now, device },
    ttlSeconds
  );
  if (!stored) {
    throw new Error('Невозможно выдать токен аутентификации: ошибка записи в Redis');
  }

  try {
    await redisClient?.sadd(`${USER_TOKENS_PREFIX}${userId}`, token);
    await redisClient?.expire(`${USER_TOKENS_PREFIX}${userId}`, ttlSeconds);
  } catch (err) {
    logger.warn({ err, userId }, 'Не удалось записать обратный указатель токена');
  }

  logger.info({ userId }, 'Auth token issued');
  return token;
}

async function resolveAuthToken(token) {
  if (!token || typeof token !== 'string' || !TOKEN_REGEX.test(token)) return null;

  const data = await get(keyFor(token));
  return data?.userId || null;
}

async function revokeAuthToken(token) {
  if (!token || typeof token !== 'string' || !TOKEN_REGEX.test(token)) return false;

  const record = await get(keyFor(token));
  const removed = await del(keyFor(token));

  if (record?.userId) {
    try {
      await redisClient?.srem(`${USER_TOKENS_PREFIX}${record.userId}`, token);
    } catch (err) {
      logger.warn({ err }, 'Не удалось убрать токен из списка пользователя');
    }
  }

  return removed;
}

const TOUCH_INTERVAL_MS = 5 * 60 * 1000;

async function touchAuthToken(token) {
  if (!token || !TOKEN_REGEX.test(token) || !isRedisAvailable()) return;

  try {
    const entry = await getWithTTL(keyFor(token));
    const record = entry?.value;
    const ttl = entry?.ttl;
    if (!record || typeof ttl !== 'number' || ttl <= 0) return;

    const now = Date.now();
    if (record.lastSeenAt && now - record.lastSeenAt < TOUCH_INTERVAL_MS) return;

    await set(keyFor(token), { ...record, lastSeenAt: now }, ttl);
  } catch (err) {
    logger.warn({ err }, 'Не удалось обновить отметку последнего визита токена');
  }
}

async function listUserTokens(userId) {
  if (!userId || !isRedisAvailable()) return [];

  const setKey = `${USER_TOKENS_PREFIX}${userId}`;

  let tokens = [];
  try {
    tokens = (await redisClient?.smembers(setKey)) || [];
  } catch (err) {
    logger.error({ err, userId }, 'Не удалось прочитать список токенов пользователя');
    return [];
  }

  const records = await Promise.all(
    tokens.map(async (token) => ({ token, record: await get(keyFor(token)) }))
  );

  const stale = records.filter(({ record }) => !record).map(({ token }) => token);
  if (stale.length > 0) {
    try {
      await redisClient?.srem(setKey, ...stale);
    } catch (err) {
      logger.warn({ err, userId }, 'Не удалось почистить истёкшие токены');
    }
  }

  return records
    .filter(({ record }) => record && record.userId === userId)
    .map(({ token, record }) => ({
      id: deviceIdFor(token),
      kind: 'app',
      device: record.device || null,
      issuedAt: record.issuedAt || null,
      lastSeenAt: record.lastSeenAt || record.issuedAt || null,
    }));
}

async function revokeUserTokenById(userId, deviceId) {
  if (!userId || !deviceId || !isRedisAvailable()) return false;

  let tokens = [];
  try {
    tokens = (await redisClient?.smembers(`${USER_TOKENS_PREFIX}${userId}`)) || [];
  } catch (err) {
    logger.error({ err, userId }, 'Не удалось прочитать список токенов пользователя');
    return false;
  }

  const match = tokens.find((token) => deviceIdFor(token) === deviceId);
  if (!match) return false;

  const record = await get(keyFor(match));
  if (record && record.userId !== userId) {
    logger.error({ userId }, 'Токен из списка пользователя принадлежит другому — пропускаем');
    return false;
  }

  await revokeAuthToken(match);
  return true;
}

async function revokeAllUserTokens(userId) {
  if (!userId) return 0;

  try {
    const setKey = `${USER_TOKENS_PREFIX}${userId}`;
    const tokens = (await redisClient?.smembers(setKey)) || [];

    await Promise.all(tokens.map((t) => del(keyFor(t))));
    await redisClient?.del(setKey);

    logger.info({ userId, count: tokens.length }, 'Все токены пользователя отозваны');
    return tokens.length;
  } catch (err) {
    logger.error({ err, userId }, 'Не удалось отозвать токены пользователя');
    return 0;
  }
}

function extractBearerToken(req) {
  const auth = req.headers?.authorization;
  if (!auth || !auth.startsWith('Bearer ')) return null;
  const value = auth.slice('Bearer '.length).trim();
  return value || null;
}

module.exports = {
  issueAuthToken,
  resolveAuthToken,
  revokeAuthToken,
  touchAuthToken,
  listUserTokens,
  revokeUserTokenById,

  revokeAllUserTokens,
  extractBearerToken,
  TOKEN_TTL_SECONDS,
};