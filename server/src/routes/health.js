const express = require('express');
const router = express.Router();
const prisma = require('../db/prisma');
const { redisClient, isRedisAvailable } = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');
const axios = require('axios');

let cachedSpotifyToken = null;
let cachedSpotifyTokenExpiresAt = 0;

let cachedSpotifyCheck = null;
let cachedSpotifyCheckAt = 0;
const SPOTIFY_CHECK_TTL_MS = 60000;

async function getSpotifyClientCredentialsToken() {
  if (cachedSpotifyToken && Date.now() < cachedSpotifyTokenExpiresAt) {
    return cachedSpotifyToken;
  }

  const auth = Buffer.from(`${process.env.SPOTIFY_CLIENT_ID}:${process.env.SPOTIFY_CLIENT_SECRET}`).toString('base64');
  const tokenResp = await axios.post(
    'https://accounts.spotify.com/api/token',
    'grant_type=client_credentials',
    {
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      timeout: 5000,
      validateStatus: () => true,
    }
  );

  if (tokenResp.status !== 200 || !tokenResp.data?.access_token) {
    throw new Error(`Spotify client credentials failure: ${tokenResp.status}`);
  }

  cachedSpotifyToken = tokenResp.data.access_token;
  const expiresInSeconds = tokenResp.data.expires_in || 3600;
  cachedSpotifyTokenExpiresAt = Date.now() + Math.max(expiresInSeconds - 60, 30) * 1000;

  return cachedSpotifyToken;
}

async function getSpotifyHealth() {
  if (cachedSpotifyCheck !== null && Date.now() - cachedSpotifyCheckAt < SPOTIFY_CHECK_TTL_MS) {
    return cachedSpotifyCheck;
  }

  const spotifyApi = process.env.SPOTIFY_API_URL || 'https://api.spotify.com/v1';
  let token = process.env.SPOTIFY_API_TOKEN || null;

  if (!token && process.env.SPOTIFY_CLIENT_ID && process.env.SPOTIFY_CLIENT_SECRET) {
    token = await getSpotifyClientCredentialsToken();
  }

  if (!token) {
    throw new Error('Spotify credentials not configured');
  }

  const response = await axios.get(`${spotifyApi}/search?q=test&type=track&limit=1`, {
    headers: { Authorization: `Bearer ${token}` },
    timeout: 5000,
    validateStatus: () => true,
  });

  if (response.status >= 400) {
    throw new Error(`Spotify returned status ${response.status}`);
  }

  cachedSpotifyCheck = true;
  cachedSpotifyCheckAt = Date.now();
  return true;
}

async function checkDatabase() {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch (err) {
    logger.error({ err }, 'Health check: database is down');
    return false;
  }
}

async function checkRedis() {
  try {
    if (!isRedisAvailable()) throw new Error('Redis unavailable');
    await redisClient.ping();
    return true;
  } catch (err) {
    logger.error({ err }, 'Health check: redis is down');
    return false;
  }
}

async function checkSpotify() {
  try {
    await getSpotifyHealth();
    return true;
  } catch (err) {
    cachedSpotifyCheck = null;
    logger.warn({ err }, 'Health check: Spotify API is unreachable');
    return false;
  }
}

router.get('/', async (req, res) => {
  const [database, redis, spotify] = await Promise.all([
    checkDatabase(),
    checkRedis(),
    checkSpotify(),
  ]);

  const checks = {
    database: database ? 'up' : 'down',
    redis: redis ? 'up' : 'down',
    spotify: spotify ? 'up' : 'down',
  };

  const criticalOk = database && redis;
  const status = criticalOk ? (spotify ? 'ok' : 'degraded') : 'down';

  res.status(criticalOk ? 200 : 503).json({ status, checks });
});

router.get('/live', (req, res) => {
  res.json({ status: 'ok', uptimeSeconds: Math.floor(process.uptime()) });
});

router.get('/ready', async (req, res) => {
  const [database, redis] = await Promise.all([checkDatabase(), checkRedis()]);
  const ready = database && redis;

  res.status(ready ? 200 : 503).json({
    status: ready ? 'ready' : 'not-ready',
    checks: {
      database: database ? 'up' : 'down',
      redis: redis ? 'up' : 'down',
    },
  });
});

module.exports = router;