const express = require('express');
const router = express.Router();
const prisma = require('../db/prisma');
const { redisClient, isRedisAvailable } = require('../infrastructure/redis');
const axios = require('axios');

async function getSpotifyHealth() {
  const spotifyApi = process.env.SPOTIFY_API_URL || 'https://api.spotify.com/v1';
  let token = process.env.SPOTIFY_API_TOKEN || null;

  if (!token && process.env.SPOTIFY_CLIENT_ID && process.env.SPOTIFY_CLIENT_SECRET) {
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

    if (tokenResp.status === 200 && tokenResp.data?.access_token) {
      token = tokenResp.data.access_token;
    } else {
      throw new Error(`Spotify client credentials failure: ${tokenResp.status}`);
    }
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

  return true;
}

router.get('/', async (req, res) => {
  const checks = {
    database: 'down',
    redis: 'down',
    spotify: 'down',
  };
  let overallOk = true;

  try {
    await prisma.$queryRaw`SELECT 1`;
    checks.database = 'up';
  } catch (err) {
    overallOk = false;
  }

  try {
    if (!isRedisAvailable()) throw new Error('Redis unavailable');
    await redisClient.ping();
    checks.redis = 'up';
  } catch (err) {
    overallOk = false;
  }

  try {
    await getSpotifyHealth();
    checks.spotify = 'up';
  } catch (err) {
    overallOk = false;
  }

  const status = overallOk ? 'ok' : 'degraded';
  res.status(overallOk ? 200 : 503).json({ status, checks });
});

module.exports = router;
