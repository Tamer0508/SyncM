const express = require('express');
const router = express.Router();
const axios = require('axios');
const prisma = require('../db/prisma');

const refreshAccessToken = async (user) => {
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
    data: { accessToken: newAccessToken },
  });

  return newAccessToken;
};

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  if (req.query.userId) return req.query.userId;
  return null;
};

router.get('/playlists', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    let user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user?.accessToken) return res.status(401).json({ error: 'Нет токена Spotify' });

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
      } else {
        throw err;
      }
    }

    const playlists = response.data.items.map(p => ({
      id: p.id,
      name: p.name,
      description: p.description,
      imageUrl: p.images?.[0]?.url || null,
      trackCount: p.tracks?.total ?? 0,
    }));

    res.json(playlists);
  } catch (error) {
    console.error('Spotify playlists error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка получения плейлистов' });
  }
});

router.get('/playlists/:playlistId/tracks', async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    let user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user?.accessToken) {
      return res.status(401).json({ error: 'Нет токена Spotify' });
    }

    let accessToken = user.accessToken;
    let response;

    try {
      response = await axios.get(
        `https://api.spotify.com/v1/playlists/${req.params.playlistId}/tracks?limit=50`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(user);
        response = await axios.get(
          `https://api.spotify.com/v1/playlists/${req.params.playlistId}/tracks?limit=50`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
      } else {
        console.error('SPOTIFY ERROR:', err.response?.data || err.message);
        throw err;
      }
    }

    const tracks = (response.data.items || [])
      .map(item => {
        const track = item?.track;
        if (!track) return null;

        return {
          id: track.id ?? null,
          name: track.name ?? 'Unknown',
          artist: Array.isArray(track.artists)
            ? track.artists.map(a => a?.name ?? '').join(', ')
            : 'Unknown',
          imageUrl:
            track.album?.images && track.album.images.length > 0
              ? track.album.images[0].url
              : null,
          uri: track.uri ?? null,
          durationMs: track.duration_ms ?? 0,
        };
      })
      .filter(Boolean);

    res.json(tracks);
  } catch (error) {
    console.error('TRACKS FULL ERROR:', error);
    res.status(500).json({ error: 'Ошибка получения треков' });
  }
});

module.exports = router;