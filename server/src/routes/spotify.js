const express = require('express');
const router = express.Router();
const axios = require('axios');
const prisma = require('../db/prisma');
const { encrypt, decrypt } = require('../utils/crypto');

const refreshAccessToken = async (spotifyUser) => {
  try {
    // Расшифровываем refresh-токен перед использованием
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
    
    // Шифруем новый токен перед сохранением
    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: {
        accessToken: encrypt(newAccessToken),
        ...(response.data.refresh_token && { refreshToken: encrypt(response.data.refresh_token) }),
      },
    });

    return newAccessToken; // Возвращаем уже расшифрованный для использования
  } catch (error) {
    console.error('Refresh token error:', error.response?.data || error.message);
    throw error;
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

router.get('/playlists', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser || !spotifyUser.accessToken) {
      return res.status(401).json({ error: 'Spotify не подключен' });
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

    const playlists = response.data.items.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      imageUrl: p.images?.[0]?.url || null,
      trackCount: p.tracks?.total ?? 0,
      owner: p.owner?.display_name,
      isPublic: p.public,
    }));

    res.json(playlists);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения плейлистов' });
  }
});

router.get('/playlists/:playlistId/tracks', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) return res.status(401).json({ error: 'Spotify не подключен' });

    let accessToken = getAccessToken(spotifyUser);
    let response;

    try {
      response = await axios.get(
        `https://api.spotify.com/v1/playlists/${req.params.playlistId}/items?limit=50&market=from_token`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(spotifyUser);
        response = await axios.get(
          `https://api.spotify.com/v1/playlists/${req.params.playlistId}/items?limit=50&market=from_token`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
      } else throw err;
    }

    const tracks = response.data.items
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

    res.json(tracks);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения треков' });
  }
});

router.get('/status', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    res.json({
      connected: !!spotifyUser,
      spotifyId: spotifyUser?.spotifyId || null,
      displayName: spotifyUser?.displayName || null,
      avatarUrl: spotifyUser?.avatarUrl || null,
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка проверки статуса' });
  }
});

router.get('/devices', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
    const accessToken = getAccessToken(spotifyUser);
    const response = await axios.get('https://api.spotify.com/v1/me/player/devices', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    res.json(response.data.devices);
  } catch (e) {
    res.status(500).json({ error: 'Ошибка получения устройств' });
  }
});

router.get('/player', async (req, res) => {
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
  } catch (e) {
    res.status(500).json({ error: 'Ошибка получения плеера' });
  }
});

router.post('/play', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { uri, deviceId } = req.body;
  if (!uri) return res.status(400).json({ error: 'Missing uri' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена Spotify' });

    let accessToken = getAccessToken(spotifyUser);

    // Если deviceId не передан — получаем список устройств и берём активное
    let targetDeviceId = deviceId;
    if (!targetDeviceId) {
      try {
        const devicesRes = await axios.get('https://api.spotify.com/v1/me/player/devices', {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        const devices = devicesRes.data.devices || [];
        
        // Сначала берём активное, потом первое доступное
        const active = devices.find(d => d.is_active);
        const first = devices[0];
        const device = active || first;
        
        if (device) {
          targetDeviceId = device.id;
          console.log(`Auto-selected device: ${device.name} (${device.type})`);
        } else {
          console.log('No devices available');
        }
      } catch (e) {
        console.log('Failed to get devices:', e.message);
      }
    }

    const playUrl = targetDeviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${targetDeviceId}`
      : 'https://api.spotify.com/v1/me/player/play';

    try {
      await axios.put(playUrl, { uris: [uri] }, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(spotifyUser);
        await axios.put(playUrl, { uris: [uri] }, {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
      } else {
        console.error('Play error:', err.response?.data || err.message);
        throw err;
      }
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Play error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка воспроизведения' });
  }
});

router.post('/disconnect', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) return res.status(404).json({ error: 'Spotify не подключен' });

    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: { userId: null },
    });

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка отключения Spotify' });
  }
});

router.get('/token-info', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) return res.status(401).json({ error: 'Spotify не подключен' });

    const accessToken = getAccessToken(spotifyUser);
    const response = await axios.get('https://api.spotify.com/v1/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    res.json({ spotifyUser: response.data, tokenPreview: accessToken.substring(0, 10) + '...' });
  } catch (error) {
    res.json({ error: error.message });
  }
});

router.post('/next', async (req, res) => {
  const userId = getUserId(req);
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    await axios.post('https://api.spotify.com/v1/me/player/next', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: 'Ошибка' }); }
});

router.post('/previous', async (req, res) => {
  const userId = getUserId(req);
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    await axios.post('https://api.spotify.com/v1/me/player/previous', {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: 'Ошибка' }); }
});

router.put('/seek', async (req, res) => {
  const userId = getUserId(req);
  const { position_ms } = req.query;
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
  try {
    await axios.put(`https://api.spotify.com/v1/me/player/seek?position_ms=${position_ms}`, {}, {
      headers: { Authorization: `Bearer ${getAccessToken(spotifyUser)}` },
    });
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: 'Ошибка' }); }
});

router.put('/pause', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
    const accessToken = getAccessToken(spotifyUser);
    await axios.put('https://api.spotify.com/v1/me/player/pause', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Ошибка паузы' });
  }
});

router.put('/resume', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });
  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser?.accessToken) return res.status(401).json({ error: 'Нет токена' });
    const accessToken = getAccessToken(spotifyUser);
    await axios.put('https://api.spotify.com/v1/me/player/play', {}, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: 'Ошибка возобновления' });
  }
});

module.exports = router;
