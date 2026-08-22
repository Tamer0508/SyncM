const https = require('https');
const axios = require('axios');
const prisma = require('../../db/prisma');
const { encrypt, decrypt } = require('../../utils/crypto');
const { acquireLock, releaseLock } = require('../redis');
const logger = require('../logger');

const accessTokenAad = (spotifyUserId) => `spotifyUser:${spotifyUserId}:accessToken`;
const refreshTokenAad = (spotifyUserId) => `spotifyUser:${spotifyUserId}:refreshToken`;

const spotifyAgent = new https.Agent({
  keepAlive: true,
  keepAliveMsecs: 15000,
  maxSockets: 64,
  maxFreeSockets: 16,
  timeout: 15000,
});

const spotifyHttp = axios.create({
  timeout: 10000,
  httpsAgent: spotifyAgent,
  decompress: true,
});

const REFRESH_LOCK_TTL_SECONDS = 10;
const MAX_RATE_LIMIT_RETRIES = 5;
const MAX_RETRY_AFTER_SECONDS = 10;

class SpotifyApiError extends Error {
  constructor(status, statusText, data) {
    super(`Spotify API error ${status}: ${statusText || ''}`.trim());
    this.name = 'SpotifyApiError';
    this.status = status;
    this.data = data;
  }
}

class SpotifyNotConnectedError extends Error {
  constructor(message = 'Spotify не подключён') {
    super(message);
    this.name = 'SpotifyNotConnectedError';
  }
}

async function getSpotifyUser(userId) {
  if (!userId) return null;
  return prisma.spotifyUser.findFirst({
    where: { OR: [{ userId }, { id: userId }] },
  });
}

async function getAccessToken(spotifyUser) {
  if (!spotifyUser?.accessToken) throw new SpotifyNotConnectedError('Нет access token');
  return decrypt(spotifyUser.accessToken, { aad: accessTokenAad(spotifyUser.id) });
}

async function encryptAccessToken(spotifyUserId, token) {
  return encrypt(token, { aad: accessTokenAad(spotifyUserId) });
}

async function encryptRefreshToken(spotifyUserId, token) {
  return encrypt(token, { aad: refreshTokenAad(spotifyUserId) });
}

async function refreshAccessToken(spotifyUser) {
  const lockKey = `spotify:refresh_lock:${spotifyUser.id}`;
  const lockToken = await acquireLock(lockKey, REFRESH_LOCK_TTL_SECONDS);

  if (!lockToken) {
    logger.info({ spotifyUserId: spotifyUser.id }, 'Refresh token already in progress, waiting');
    await new Promise((resolve) => setTimeout(resolve, 150));
    const fresh = await prisma.spotifyUser.findUnique({ where: { id: spotifyUser.id } });
    if (fresh?.accessToken) {
      try {
        const newToken = await getAccessToken(fresh);
        if (newToken) return newToken;
      } catch (err) {
        logger.warn({ err, spotifyUserId: spotifyUser.id }, 'Could not read token written by concurrent refresh');
      }
    }
    throw new Error('Could not obtain fresh Spotify token');
  }

  try {
    const refreshToken = await decrypt(spotifyUser.refreshToken, {
      aad: refreshTokenAad(spotifyUser.id),
    });
    if (!refreshToken) throw new Error('Не удалось расшифровать refresh token');

    const response = await spotifyHttp.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refreshToken }),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${Buffer.from(
            `${process.env.SPOTIFY_CLIENT_ID}:${process.env.SPOTIFY_CLIENT_SECRET}`
          ).toString('base64')}`,
        },
        timeout: 10000,
      }
    );

    const newAccessToken = response.data.access_token;
    if (!newAccessToken) throw new Error('Spotify не вернул access_token');

    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: {
        accessToken: await encryptAccessToken(spotifyUser.id, newAccessToken),
        ...(response.data.refresh_token && {
          refreshToken: await encryptRefreshToken(spotifyUser.id, response.data.refresh_token),
        }),
      },
    });

    return newAccessToken;
  } catch (err) {
    logger.error({ err, spotifyUserId: spotifyUser.id }, 'Refresh token error');
    throw err;
  } finally {
    await releaseLock(lockKey, lockToken);
  }
}

async function spotifyRequest(spotifyUser, config, { attempt = 1, accessToken = null } = {}) {
  let token = accessToken || (await getAccessToken(spotifyUser));

  const send = (bearer) =>
    spotifyHttp({
      ...config,
      headers: { ...(config.headers || {}), Authorization: `Bearer ${bearer}` },
      validateStatus: (status) => status < 500,
    });

  let response = await send(token);

  if (response.status === 401) {
    logger.info({ spotifyUserId: spotifyUser.id }, 'Spotify token expired, refreshing');
    token = await refreshAccessToken(spotifyUser);
    response = await send(token);
  }

  if (response.status === 429 && attempt <= MAX_RATE_LIMIT_RETRIES) {
    const retryAfter = parseInt(response.headers['retry-after'], 10) || 5;
    if (retryAfter > MAX_RETRY_AFTER_SECONDS) {
      logger.warn(
        { url: config.url, retryAfter },
        'Spotify rate limit window too long to wait out, failing fast'
      );
      throw new SpotifyApiError(429, 'Too Many Requests', response.data);
    }
    logger.warn({ url: config.url, attempt, retryAfter }, 'Spotify rate limited, retrying');
    await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
    return spotifyRequest(spotifyUser, config, { attempt: attempt + 1, accessToken: token });
  }

  if (response.status >= 400) {
    throw new SpotifyApiError(response.status, response.statusText, response.data);
  }

  return response;
}

const spotifyGet = async (spotifyUser, url) =>
  (await spotifyRequest(spotifyUser, { method: 'get', url })).data;

module.exports = {
  spotifyHttp,
  accessTokenAad,
  refreshTokenAad,
  getSpotifyUser,
  getAccessToken,
  encryptAccessToken,
  encryptRefreshToken,
  refreshAccessToken,
  spotifyRequest,
  spotifyGet,
  SpotifyApiError,
  SpotifyNotConnectedError,
};