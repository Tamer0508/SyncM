const express = require('express');
const router = express.Router();
const prisma = require('../db/prisma');
const redis = require('../infrastructure/redis');
const axios = require('axios');

router.get('/', async (req, res) => {
  const checks = {};
  let overallOk = true;

  // Database check
  try {
    // Simple lightweight query
    await prisma.$queryRaw`SELECT 1`;
    checks.database = { ok: true };
  } catch (err) {
    checks.database = { ok: false, error: err?.message || String(err) };
    overallOk = false;
  }

  // Redis check
  try {
    if (redis.isRedisAvailable && redis.isRedisAvailable()) {
      const pong = await redis.redisClient.ping();
      checks.redis = { ok: true, pong };
    } else {
      checks.redis = { ok: false, error: 'Redis not available' };
      overallOk = false;
    }
  } catch (err) {
    checks.redis = { ok: false, error: err?.message || String(err) };
    overallOk = false;
  }

  // Spotify API check
  try {
    const spotifyBase = process.env.SPOTIFY_API_URL || 'https://api.spotify.com/v1';
    const resp = await axios.get(spotifyBase, { timeout: 2000, validateStatus: () => true });
    // treat 5xx as failure; 4xx means reachable but unauthorized
    if (resp.status >= 500) {
      checks.spotify = { ok: false, status: resp.status };
      overallOk = false;
    } else {
      checks.spotify = { ok: true, status: resp.status };
    }
  } catch (err) {
    checks.spotify = { ok: false, error: err?.message || String(err) };
    overallOk = false;
  }

  const status = overallOk ? 'ok' : 'degraded';
  const code = overallOk ? 200 : 503;
  res.status(code).json({ status, checks });
});

module.exports = router;
