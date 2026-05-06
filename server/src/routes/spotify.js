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
    
    // Сохраняем новый токен и refresh_token если он обновился
    await prisma.user.update({
      where: { id: user.id },
      data: { 
        accessToken: newAccessToken,
        ...(response.data.refresh_token && { 
          refreshToken: response.data.refresh_token 
        })
      },
    });
    
    return newAccessToken;
  } catch (error) {
    console.error('Refresh token error:', error.response?.data || error.message);
    throw error;
  }
};

const getUserId = (req) => {
  console.log('Auth header:', req.headers.authorization);
  console.log('Session userId:', req.session?.userId);
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const getSpotifyUser = async (userId) => {
  // Сначала проверяем — может userId уже является Spotify User
  let user = await prisma.user.findUnique({ where: { id: userId } });
  if (user) return user;
 
  // Иначе ищем через AppUser → User по полю app_user_id
  user = await prisma.user.findUnique({ where: { app_user_id: userId } });
  return user;
};

router.get('/playlists', async (req, res) => {
  const userId = getUserId(req);
  console.log('Playlists request - userId:', userId);
  
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    let user = await getSpotifyUser(userId);
    console.log('Spotify user found:', !!user);
    
    if (!user) {
      return res.status(401).json({ 
        error: 'Spotify не подключен',
        message: 'Пожалуйста, подключите Spotify аккаунт в настройках профиля'
      });
    }
    
    if (!user.accessToken) {
      return res.status(401).json({ error: 'Нет токена Spotify' });
    }

    let accessToken = user.accessToken;
    let response;

    try {
      console.log('Fetching playlists with token');
      response = await axios.get('https://api.spotify.com/v1/me/playlists?limit=20', {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
    } catch (err) {
      if (err.response?.status === 401) {
        accessToken = await refreshAccessToken(user);
        response = await axios.get(
          `https://api.spotify.com/v1/playlists/${req.params.playlistId}/tracks?limit=50`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
      } else if (err.response?.status === 403) {
        return res.status(403).json({ 
          error: 'Нет доступа к плейлисту',
          details: 'Плейлист приватный или требует других прав доступа'
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
      owner: p.owner?.display_name,
      isPublic: p.public
    }));

    console.log(`Found ${playlists.length} playlists`);
    res.json(playlists);
  } catch (error) {
    console.error('Spotify playlists error:', error.response?.data || error.message);
    res.status(500).json({ 
      error: 'Ошибка получения плейлистов',
      details: error.response?.data || error.message 
    });
  }
});

router.get('/playlists/:playlistId/tracks', async (req, res) => {
  console.log('Fetching tracks for playlistId:', req.params.playlistId);
  const userId = getUserId(req);
  
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    let user = await getSpotifyUser(userId);
    if (!user) {
      return res.status(401).json({ 
        error: 'Spotify не подключен',
        message: 'Пожалуйста, подключите Spotify аккаунт'
      });
    }
    
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
        throw err;
      }
    }

    const tracks = response.data.items
      .filter(item => item.track)
      .map(item => ({
        id: item.track.id,
        name: item.track.name,
        artist: item.track.artists.map(a => a.name).join(', '),
        imageUrl: item.track.album.images?.[0]?.url || null,
        uri: item.track.uri,
        durationMs: item.track.duration_ms,
        album: item.track.album.name,
        previewUrl: item.track.preview_url
      }));

    console.log(`Found ${tracks.length} tracks`);
    res.json(tracks);
  } catch (error) {
    console.error('Tracks error:', error.response?.data || error.message);
    res.status(500).json({ 
      error: 'Ошибка получения треков',
      details: error.response?.data || error.message 
    });
  }
});

// Добавим эндпоинт для проверки статуса подключения Spotify
router.get('/status', async (req, res) => {
  const userId = getUserId(req);
  
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await getSpotifyUser(userId);
    
    res.json({
      connected: !!user,
      spotifyId: user?.spotifyId || null,
      displayName: user?.displayName || null,
      avatarUrl: user?.avatarUrl || null
    });
  } catch (error) {
    console.error('Status error:', error);
    res.status(500).json({ error: 'Ошибка проверки статуса' });
  }
});

router.post('/disconnect', async (req, res) => {
  const userId = getUserId(req);
  
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await getSpotifyUser(userId);
    
    if (!user) {
      return res.status(404).json({ error: 'Spotify не подключен' });
    }

    // Отвязываем Spotify от AppUser
    await prisma.user.update({
      where: { id: user.id },
      data: { AppUser: { disconnect: true } }
    });

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    console.error('Disconnect error:', error);
    res.status(500).json({ error: 'Ошибка отключения Spotify' });
  }
});

module.exports = router;