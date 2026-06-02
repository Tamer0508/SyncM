const express = require('express');
const router = express.Router();
const axios = require('axios');
const prisma = require('../db/prisma');
const { encrypt, decrypt } = require('../utils/crypto');
const { getOrSet } = require('../infrastructure/spotify/cache');
const { acquireLock, releaseLock } = require('../infrastructure/redis');
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');

const refreshAccessToken = async (spotifyUser) => {
  const lockKey = `spotify:refresh_lock:${spotifyUser.id}`;
  // Пытаемся захватить блокировку на 5 секунд
  const locked = await acquireLock(lockKey, 5);
  if (!locked) {
    // Если не удалось захватить блокировку – ждём чуть-чуть и читаем новый токен из БД
    console.log(` Refresh token already in progress for user ${spotifyUser.id}, waiting...`);
    await new Promise(resolve => setTimeout(resolve, 100));
    // Повторно получаем пользователя из БД – возможно, токен уже обновлён другим процессом
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
    console.error('Refresh token error:', error.response?.data || error.message);
    throw error;
  } finally {
    await releaseLock(lockKey);
  }
};

// Хелпер: получить расшифрованный access token
const getAccessToken = (spotifyUser) => {
  return decrypt(spotifyUser.accessToken);
};

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

// Ищем Spotify-аккаунт по ID пользователя или по ID самого Spotify-аккаунта
const getSpotifyUser = async (userId) => {
  if (!userId) return null;
  return await prisma.spotifyUser.findFirst({
    where: { OR: [{ userId }, { id: userId }] }
  });
};

const extractTrack = (item) => item.item || item.track || null;

router.get('/playlists', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:user-playlists:${userId}`;

  try {
    const playlists = await getOrSet(cacheKey, null, async () => {
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
    console.error('Error in /playlists:', error.message);
    res.status(500).json({ error: 'Ошибка получения плейлистов' });
  }
});

router.get('/playlists/:playlistId/tracks', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = req.params;
  const cacheKey = `spotify:playlist:${playlistId}:items`;

  try {
    const tracks = await getOrSet(cacheKey, null, async () => {
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
    console.error('Error fetching tracks:', error.message);
    res.status(500).json({ error: 'Ошибка получения треков' });
  }
});

router.get('/status', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:status:${userId}`;

  try {
    const status = await getOrSet(cacheKey, 300, async () => {
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
    const devices = await getOrSet(cacheKey, null, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser?.accessToken) throw new Error('Нет токена');

      const accessToken = getAccessToken(spotifyUser);
      const response = await axios.get('https://api.spotify.com/v1/me/player/devices', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      return response.data.devices;
    });

    res.json(devices);
  } catch (e) {
    console.error('Devices error:', e.message);
    res.status(500).json({ error: 'Ошибка получения устройств' });
  }
});

router.get('/player', rateLimitMiddleware(30, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:player:${userId}`;

  try {
    const playerState = await getOrSet(cacheKey, 10, async () => {
      const spotifyUser = await getSpotifyUser(userId);
      if (!spotifyUser?.accessToken) throw new Error('Нет токена');

      const accessToken = getAccessToken(spotifyUser);
      const response = await axios.get('https://api.spotify.com/v1/me/player', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (response.status === 204) return null;
      return response.data;
    });

    res.json(playerState);
  } catch (e) {
    console.error('Player state error:', e.message);
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
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена Spotify' });

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
      } else throw err;
    }

    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);

    res.json({ success: true });
  } catch (error) {
    console.error('Play error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка воспроизведения' });
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

    await invalidateUserCache(userId, [
      `spotify:status:${userId}`,
      `spotify:token-info:${userId}`,
      `spotify:user-playlists:${userId}`,
    ]);

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка отключения Spotify' });
  }
});

router.get('/token-info', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `spotify:token-info:${userId}`;

  try {
    const info = await getOrSet(cacheKey, 600, async () => {
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
  console.log('Skip next, userId:', userId);
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    const accessToken = getAccessToken(spotifyUser);
    console.log('Calling Spotify next, token:', accessToken.substring(0, 10));
    const result = await axios.post('https://api.spotify.com/v1/me/player/next', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    console.log('Skip next result:', result.status);
    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);

    res.json({ success: true });
  } catch (e) {
    console.error('Skip next error:', e.response?.data || e.message);
    res.status(500).json({ error: 'Ошибка' });
  }
});

router.post('/previous', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    await axios.post('https://api.spotify.com/v1/me/player/previous', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: 'Ошибка' }); }
});

router.put('/seek', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  const { position_ms } = req.query;
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    await axios.put(`https://api.spotify.com/v1/me/player/seek?position_ms=${position_ms}`, {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: 'Ошибка' }); }
});

router.put('/pause', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
    const accessToken = getAccessToken(spotifyUser);
    await axios.put('https://api.spotify.com/v1/me/player/pause', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Ошибка паузы' });
  }
});

router.put('/resume', rateLimitMiddleware(20, 60), async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
    const accessToken = getAccessToken(spotifyUser);
    await axios.put('https://api.spotify.com/v1/me/player/play', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    await invalidateUserCache(userId, [`spotify:player:${userId}`, `spotify:devices:${userId}`]);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Ошибка возобновления' });
  }
});

module.exports = router;
