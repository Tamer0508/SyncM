const express = require('express');
const router = express.Router();
const axios = require('axios');
const prisma = require('../db/prisma');

const refreshAccessToken = async (user) => {
  try {
    const response = await axios.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: user.refreshToken,
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
    await prisma.user.update({
      where: { id: user.id },
      data: {
        accessToken: newAccessToken,
        ...(response.data.refresh_token && { refreshToken: response.data.refresh_token }),
      },
    });

    return newAccessToken;
  } catch (error) {
    console.error('Refresh token error:', error.response?.data || error.message);
    throw error;
  }
};

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const getSpotifyUser = async (userId) => {
  // Ищем по app_user_id (связь с AppUser) или по id (если это старый формат сессии)
  return await prisma.user.findFirst({
    where: { OR: [{ app_user_id: userId }, { id: userId }] }
  });
};

const extractTrack = (item) => {
  return item.item || item.track || null;
};

router.get('/playlists', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await getSpotifyUser(userId);
    if (!user || !user.accessToken) {
      return res.status(401).json({ error: 'Spotify не подключен' });
    }

    let accessToken = user.accessToken;
    let response;

    try {
      response = await axios.get('https://api.spotify.com/v1/me/playlists?limit=20', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(user);
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
    const user = await getSpotifyUser(userId);
    if (!user) return res.status(401).json({ error: 'Spotify не подключен' });

    let accessToken = user.accessToken;
    let response;

    try {
      response = await axios.get(
        `https://api.spotify.com/v1/playlists/${req.params.playlistId}/items?limit=50&market=from_token`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(user);
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
    const user = await getSpotifyUser(userId);
    res.json({
      connected: !!user,
      spotifyId: user?.spotifyId || null,
      displayName: user?.displayName || null,
      avatarUrl: user?.avatarUrl || null,
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка проверки статуса' });
  }
});

router.post('/disconnect', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await getSpotifyUser(userId);
    if (!user) return res.status(404).json({ error: 'Spotify не подключен' });

    await prisma.user.update({
      where: { id: user.id },
      data: { app_user_id: null },
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
    let user = await getSpotifyUser(userId);
    if (!user) return res.status(401).json({ error: 'Spotify не подключен' });

    const response = await axios.get('https://api.spotify.com/v1/me', {
      headers: { Authorization: `Bearer ${user.accessToken}` },
    });
    res.json({ spotifyUser: response.data, tokenPreview: user.accessToken.substring(0, 10) + '...' });
  } catch (error) {
    res.json({ error: error.message });
  }
});

module.exports = router;
