const crypto = require('crypto');
const { set, get, del, isRedisAvailable, redisClient } = require('./redis');
const logger = require('./logger');


const TOKEN_BYTES = 32;
const TOKEN_REGEX = /^[a-f0-9]{64}$/;
const KEY_PREFIX = 'authtoken:';

const USER_TOKENS_PREFIX = 'authtokens:user:';

const TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60;

function keyFor(token) {
  return `${KEY_PREFIX}${token}`;
}

async function issueAuthToken(userId, { ttlSeconds = TOKEN_TTL_SECONDS } = {}) {
  if (!userId) throw new Error('issueAuthToken: userId обязателен');

  if (!isRedisAvailable()) {
    throw new Error('Невозможно выдать токен аутентификации: Redis недоступен');
  }

  const token = crypto.randomBytes(TOKEN_BYTES).toString('hex');
  const stored = await set(keyFor(token), { userId, issuedAt: Date.now() }, ttlSeconds);
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
  return del(keyFor(token));
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

  revokeAllUserTokens,
  extractBearerToken,
  TOKEN_TTL_SECONDS,
};