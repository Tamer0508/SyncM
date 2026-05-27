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

router.post('/play', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { uri, deviceId } = req.body;
  if (!uri) return res.status(400).json({ error: 'Missing uri' });

  try {
    let user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      const appUser = await prisma.appUser.findUnique({
        where: { id: userId },
        include: { User: true },
      });
      user = appUser?.User || null;
    }
    if (!user?.accessToken) return res.status(401).json({ error: 'Нет токена Spotify' });

    let accessToken = user.accessToken;

    const playUrl = deviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${deviceId}`
      : 'https://api.spotify.com/v1/me/player/play';

    try {
      await axios.put(playUrl,
        { uris: [uri] },
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(user);
        await axios.put(playUrl,
          { uris: [uri] },
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
      } else {
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

module.exports = router;
