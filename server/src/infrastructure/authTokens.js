const crypto = require('crypto');
const { set, get, del, isRedisAvailable } = require('./redis');
const logger = require('./logger');


const TOKEN_BYTES = 32;
const TOKEN_REGEX = /^[a-f0-9]{64}$/;
const KEY_PREFIX = 'authtoken:';

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
  extractBearerToken,
  TOKEN_TTL_SECONDS,
};