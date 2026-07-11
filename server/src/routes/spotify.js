const express = require('express');
const router = express.Router();
const axios = require('axios');
const prisma = require('../db/prisma');
const { encrypt, decrypt } = require('../utils/crypto');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const { acquireLock, releaseLock } = require('../infrastructure/redis');
const redis = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');

const refreshAccessToken = async (spotifyUser) => {
  const lockKey = `spotify:refresh_lock:${spotifyUser.id}`;
  const locked = await acquireLock(lockKey, 5);
  if (!locked) {
    logger.info({ userId: spotifyUser.id }, 'Refresh token already in progress, waiting');
    await new Promise(resolve => setTimeout(resolve, 100));
    const freshSpotifyUser = await prisma.spotifyUser.findUnique({
      where: { id: spotifyUser.id }
    });
    if (freshSpotifyUser && freshSpotifyUser.accessToken) {
      const newToken = decrypt(freshSpotifyUser.accessToken);
      if (newToken) return newToken;
    }
    throw new Error('Could not obtain fresh token');
  }

  try {
    const decryptedRefreshToken = decrypt(spotifyUser.refreshToken);
    if (!decryptedRefreshToken) {
      throw new Error('Не удалось расшифровать refresh token');
    }

    const response = await axios.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: decryptedRefreshToken,
      }),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${Buffer.from(
            `${process.env.SPOTIFY_CLIENT_ID}:${process.env.SPOTIFY_CLIENT_SECRET}`
          ).toString('base64')}`,
        },
      }
    );

    const newAccessToken = response.data.access_token;
    
    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: {
        accessToken: encrypt(newAccessToken),
        ...(response.data.refresh_token && { refreshToken: encrypt(response.data.refresh_token) }),
      },
    });

    return newAccessToken;
  } catch (error) {
    logger.error({ err: error, spotifyUserId: spotifyUser?.id }, 'Refresh token error');
    throw error;
  } finally {
    await releaseLock(lockKey);
  }
};

const getAccessToken = (spotifyUser) => {
  return decrypt(spotifyUser.accessToken);
};

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const getSpotifyUser = async (userId) => {
  if (!userId) return null;
  return await prisma.spotifyUser.findFirst({
    where: { OR: [{ userId }, { id: userId }] }
  });
};

const extractTrack = (item) => item.item || item.track || null;

// Вспомогательные TTL для кэша (секунды)
const CACHE_TTL = {
  userPlaylists: 600,
  playlistTracks: 1800,
  status: 300,
  devices: 120,
  tokenInfo: 600,
};

router.get('/playlists', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:user-playlists:${userId}`;

  try {
    const playlists = await getOrSet(cacheKey, CACHE_TTL.userPlaylists, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser || !spotifyUser.accessToken) {
        throw new Error('Spotify не подключен');
      }

      let accessToken = getAccessToken(spotifyUser);
      let response;

      try {
        response = await axios.get('https://api.spotify.com/v1/me/playlists?limit=20', {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
      } catch (err) {
        if (err.response?.status === 401) {
          accessToken = await refreshAccessToken(spotifyUser);
          response = await axios.get('https://api.spotify.com/v1/me/playlists?limit=20', {
            headers: { Authorization: `Bearer ${accessToken}` },
          });
        } else throw err;
      }

      return response.data.items.map((p) => ({
        id: p.id,
        name: p.name,
        description: p.description,
        imageUrl: p.images?.[0]?.url || null,
        trackCount: p.tracks?.total ?? 0,
        owner: p.owner?.display_name,
        isPublic: p.public,
      }));
    });

    res.json(playlists);
  } catch (error) {
    logger.error({ err: error }, 'Error in /playlists');
    res.status(500).json({ error: 'Ошибка получения плейлистов' });
  }
});

router.get('/playlists/:playlistId/tracks', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = req.params;
  const cacheKey = `spotify:playlist:${playlistId}:items`;

  try {
    const tracks = await getOrSet(cacheKey, CACHE_TTL.playlistTracks, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser) throw new Error('Spotify не подключен');

      let accessToken = getAccessToken(spotifyUser);
      let response;

      try {
        response = await axios.get(
          `https://api.spotify.com/v1/playlists/${playlistId}/items?limit=50&market=from_token`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
      } catch (err) {
        if (err.response?.status === 401) {
          accessToken = await refreshAccessToken(spotifyUser);
          response = await axios.get(
            `https://api.spotify.com/v1/playlists/${playlistId}/items?limit=50&market=from_token`,
            { headers: { Authorization: `Bearer ${accessToken}` } }
          );
        } else throw err;
      }

      return response.data.items
        .map((item) => extractTrack(item))
        .filter((track) => track !== null)
        .map((track) => ({
          id: track.id,
          name: track.name,
          artist: track.artists?.map((a) => a.name).join(', ') ?? '',
          imageUrl: track.album?.images?.[0]?.url || null,
          uri: track.uri,
          durationMs: track.duration_ms,
          album: track.album?.name ?? '',
        }));
    });

    res.json(tracks);
  } catch (error) {
    logger.error({ err: error }, 'Error fetching tracks');
    res.status(500).json({ error: 'Ошибка получения треков' });
  }
});

router.get('/status', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:status:${userId}`;

  try {
    const status = await getOrSet(cacheKey, CACHE_TTL.status, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      return {
        connected: !!spotifyUser,
        spotifyId: spotifyUser?.spotifyId || null,
        displayName: spotifyUser?.displayName || null,
        avatarUrl: spotifyUser?.avatarUrl || null,
      };
    });
    res.json(status);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка проверки статуса' });
  }
});

router.get('/devices', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:devices:${userId}`;

  try {
    const devices = await getOrSet(cacheKey, CACHE_TTL.devices, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser?.accessToken) throw new Error('Нет токена');

      const accessToken = getAccessToken(spotifyUser);
      const response = await axios.get('https://api.spotify.com/v1/me/player/devices', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      return response.data.devices;
    });

    res.json(devices);
  } catch (error) {
    logger.error({ err: error }, 'Devices error');
    res.status(500).json({ error: 'Ошибка получения устройств' });
  }
});

router.get('/player', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });

    const accessToken = getAccessToken(spotifyUser);
    const response = await axios.get('https://api.spotify.com/v1/me/player', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (response.status === 204) return res.json(null);
    res.json(response.data);
  } catch (error) {
    logger.error({ err: error }, 'Player state error');
    res.status(500).json({ error: 'Ошибка получения плеера' });
  }
});

router.post('/play', rateLimitMiddleware(15, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { uri, deviceId, contextUri, offset } = req.body;
  if (!uri && !contextUri) return res.status(400).json({ error: 'Missing uri or contextUri' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) {
      return res.status(409).json({ error: 'Spotify не подключён' });
    }

    let accessToken = getAccessToken(spotifyUser);
    const playUrl = deviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${deviceId}`
      : 'https://api.spotify.com/v1/me/player/play';

    let body;
    if (contextUri) {
      body = { context_uri: contextUri };
      if (offset !== undefined) body.offset = { position: offset };
    } else {
      body = { uris: [uri] };
    }

    try {
      await axios.put(playUrl, body, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(spotifyUser);
        await axios.put(playUrl, body, {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
      } else {
        throw err;
      }
    }

    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
    return res.json({ success: true });
  } catch (error) {
    logger.error({ err: error }, 'Play error');
    const status = error?.response?.status;
    if (status === 404) {
      return res.status(409).json({ error: 'Нет активного устройства Spotify. Откройте Spotify и начните любое воспроизведение, затем повторите.' });
    }
    return res.status(502).json({ error: 'Не удалось запустить воспроизведение' });
  }
});

router.post('/disconnect', rateLimitMiddleware(10, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) return res.status(404).json({ error: 'Spotify не подключен' });

    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: { userId: null },
    });

    // Инвалидация кэша через глобальное версионирование
    await incrementVersion();

    await Promise.all([
      redis.del(`spotify:status:${userId}`),
      redis.del(`spotify:token-info:${userId}`),
      redis.del(`spotify:user-playlists:${userId}`),
    ]);

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    logger.error({ err: error }, 'Disconnect error');
    res.status(500).json({ error: 'Ошибка отключения Spotify' });
  }
});

router.get('/token-info', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:token-info:${userId}`;

  try {
    const info = await getOrSet(cacheKey, CACHE_TTL.tokenInfo, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser) throw new Error('Spotify не подключен');

      const accessToken = getAccessToken(spotifyUser);
      const response = await axios.get('https://api.spotify.com/v1/me', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      return { spotifyUser: response.data, tokenPreview: accessToken.substring(0, 10) + '...' };
    });
    res.json(info);
  } catch (error) {
    res.json({ error: error.message });
  }
});

router.post('/next', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return;
    const accessToken = getAccessToken(spotifyUser);
    await axios.post('https://api.spotify.com/v1/me/player/next', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (e) {
    logger.error({ err: e }, 'Skip next error');
  }
});

router.post('/previous', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return;
    await axios.post('https://api.spotify.com/v1/me/player/previous', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (e) {
    logger.error({ err: e }, 'Previous error');
  }
});

router.put('/volume', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) {
      return res.status(409).json({ error: 'Spotify не подключён' });
    }
    const { volume_percent } = req.query;
    await axios.put(`https://api.spotify.com/v1/me/player/volume?volume_percent=${volume_percent}`, {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    return res.json({ success: true });
  } catch (error) {
    logger.error({ err: error }, 'Volume error');
    const status = error?.response?.status;
    if (status === 404) {
      return res.status(409).json({ error: 'Нет активного устройства Spotify' });
    }
    return res.status(502).json({ error: 'Не удалось изменить громкость' });
  }
});

router.put('/seek', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) {
      return res.status(409).json({ error: 'Spotify не подключён' });
    }
    const { position_ms } = req.query;
    await axios.put(`https://api.spotify.com/v1/me/player/seek?position_ms=${position_ms}`, {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
    return res.json({ success: true });
  } catch (error) {
    logger.error({ err: error }, 'Seek error');
    const status = error?.response?.status;
    if (status === 404) {
      return res.status(409).json({ error: 'Нет активного устройства Spotify' });
    }
    return res.status(502).json({ error: 'Не удалось перемотать трек' });
  }
});

router.put('/pause', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return;
    await axios.put('https://api.spotify.com/v1/me/player/pause', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (error) {
    logger.error({ err: error }, 'Pause error');
  }
});

router.put('/resume', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return;
    await axios.put('https://api.spotify.com/v1/me/player/play', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (error) {
    logger.error({ err: error }, 'Resume error');
  }
});

// Shuffle и Repeat (без изменений, только импорты уже обновлены)
router.put('/shuffle', rateLimitMiddleware(10, 60), async (req, res) => {
  const userId = getUserId(req);
  logger.info({ userId, state: req.query.state }, 'Shuffle request received');
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { state } = req.query;
  if (state !== 'true' && state !== 'false') {
    return res.status(400).json({ error: 'Параметр state должен быть true или false' });
  }

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) {
      logger.warn({ userId }, 'Shuffle request has no Spotify user');
      return;
    }
    if (!spotifyUser.accessToken) {
      logger.warn({ userId }, 'Shuffle request Spotify user has no access token');
      return;
    }

    let accessToken;
    try {
      accessToken = getAccessToken(spotifyUser);
    } catch (decryptError) {
      logger.error({ userId, err: decryptError }, 'Shuffle decrypt error');
      return;
    }

    const url = `https://api.spotify.com/v1/me/player/shuffle?state=${state}`;

    try {
      await axios.put(url, {}, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      logger.info({ userId }, 'Shuffle command sent to Spotify');
    } catch (err) {
      if (err.response?.status === 401) {
        logger.info({ userId }, 'Shuffle token expired, refreshing');
        accessToken = await refreshAccessToken(spotifyUser);
        await axios.put(url, {}, {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        logger.info({ userId }, 'Shuffle command sent after token refresh');
      } else {
        logger.error({ err, userId, status: err.response?.status, data: err.response?.data }, 'Shuffle Spotify API error');
        throw err;
      }
    }

    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (error) {
    logger.error({ err: error, userId }, 'Shuffle error');
  }
});

router.put('/repeat', rateLimitMiddleware(10, 60), async (req, res) => {
  const userId = getUserId(req);
  logger.info({ userId, state: req.query.state }, 'Repeat request received');
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { state } = req.query;
  const validStates = ['off', 'context', 'track'];
  if (!validStates.includes(state)) {
    return res.status(400).json({ error: 'Параметр state должен быть off, context или track' });
  }

  res.json({ success: true });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) {
      logger.warn({ userId }, 'Repeat request has no Spotify user');
      return;
    }
    if (!spotifyUser.accessToken) {
      logger.warn({ userId }, 'Repeat request Spotify user has no access token');
      return;
    }

    let accessToken;
    try {
      accessToken = getAccessToken(spotifyUser);
    } catch (decryptError) {
      logger.error({ err: decryptError, userId }, 'Repeat decrypt error');
      return;
    }

    const url = `https://api.spotify.com/v1/me/player/repeat?state=${state}`;

    try {
      await axios.put(url, {}, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      logger.info({ userId }, 'Repeat command sent to Spotify');
    } catch (err) {
      if (err.response?.status === 401) {
        logger.info({ userId }, 'Repeat token expired, refreshing');
        accessToken = await refreshAccessToken(spotifyUser);
        await axios.put(url, {}, {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        logger.info({ userId }, 'Repeat command sent after token refresh');
      } else {
        logger.error({ err, userId, status: err.response?.status, data: err.response?.data }, 'Repeat Spotify API error');
        throw err;
      }
    }

    await Promise.all([
      redis.del(`spotify:player:${userId}`),
      redis.del(`spotify:devices:${userId}`),
    ]);
  } catch (error) {
    logger.error({ err: error, userId }, 'Repeat error');
  }
});

module.exports = router;