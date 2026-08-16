const express = require('express');
const router = express.Router();
const { z } = require('zod');
const requireAuth = require('../middleware/requireAuth');
router.use(requireAuth);
const prisma = require('../db/prisma');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');
const { rateLimitMiddleware } = require('../infrastructure/rateLimiter');
const asyncHandler = require('../utils/asyncHandler');
const {
  getSpotifyUser,
  spotifyRequest,
  spotifyGet,
  SpotifyApiError,
  SpotifyNotConnectedError,
} = require('../infrastructure/spotify/auth');

const getUserId = (req) => req.userId || req.session?.userId || null;

const extractTrack = (item) => item.item || item.track || null;

const CACHE_TTL = {
  userPlaylists: 600,
  playlistTracks: 1800,
  status: 300,
  devices: 120,
  tokenInfo: 600,
};

const volumeSchema = z.object({
  volume_percent: z.coerce.number().int().min(0).max(100),
});

const seekSchema = z.object({
  position_ms: z.coerce.number().int().min(0),
});

const shuffleSchema = z.object({
  state: z.enum(['true', 'false']),
});

const repeatSchema = z.object({
  state: z.enum(['off', 'context', 'track']),
});

const playlistIdParamsSchema = z.object({
  playlistId: z.string().min(1),
});

const playBodySchema = z
  .object({
    uri: z.string().min(1).optional(),
    deviceId: z.string().min(1).optional(),
    contextUri: z.string().min(1).optional(),
    offset: z.number().int().min(0).optional(),
  })
  .refine((b) => b.uri || b.contextUri, {
    message: 'Требуется uri или contextUri',
  });

function handleSpotifyError(res, error, context) {
  if (error instanceof SpotifyNotConnectedError) {
    return res.status(409).json({ error: 'Spotify не подключён' });
  }
  if (error instanceof SpotifyApiError) {
    logger.warn({ err: error, status: error.status, ...context }, 'Spotify API error');
    if (error.status === 404) {
      return res.status(409).json({ error: 'Нет активного устройства Spotify' });
    }
    if (error.status === 403) {
      return res.status(403).json({ error: 'Действие недоступно (нужен Spotify Premium или другое устройство)' });
    }
    if (error.status === 429) {
      return res.status(429).json({ error: 'Spotify временно ограничил запросы, попробуйте позже' });
    }
    return res.status(502).json({ error: 'Ошибка Spotify API' });
  }
  logger.error({ err: error, ...context }, 'Unexpected Spotify route error');
  return res.status(500).json({ error: 'Внутренняя ошибка' });
}

async function requireSpotifyUser(userId) {
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) throw new SpotifyNotConnectedError();
  return spotifyUser;
}

const invalidatePlaybackCaches = (userId) => incrementVersion(`spotify:devices:${userId}`);

router.get('/playlists', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const playlists = await getOrSet(`spotify:user-playlists:${userId}`, 'list', CACHE_TTL.userPlaylists, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const all = [];
      let nextUrl = 'https://api.spotify.com/v1/me/playlists?limit=50';

      while (nextUrl && all.length < 500) {
        const page = await spotifyGet(spotifyUser, nextUrl);
        all.push(...(page.items || []));
        nextUrl = page.next;
      }

      const data = { items: all };

      return data.items.map((p) => ({
        id: p.id,
        name: p.name,
        description: p.description,
        imageUrl: p.images?.[0]?.url || null,
        // tracks.total -> items.total (февральская миграция 2026). Без этого
        // в списке у всех плейлистов показывалось «0 треков».
        trackCount: p.items?.total ?? p.tracks?.total ?? 0,
        owner: p.owner?.display_name,
        isPublic: p.public,
      }));
    });

    res.json(playlists);
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/playlists' });
  }
}));

router.get('/playlists/:playlistId/tracks', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  try {
    // Ключ включает userId, а пространство имён остаётся привязанным к
    // плейлисту.
    //
    // Общий на всех ключ был утечкой: содержимое приватного плейлиста,
    // однажды загруженное его владельцем, отдавалось любому, кто знает id, —
    // проверка прав выполняется внутри fetchFn и на попадании в кэш не
    // срабатывает вовсе. Теперь у каждого своя запись, и каждый получает её
    // только после собственного запроса к Spotify, который и решает, есть ли
    // у него доступ. Инвалидация по namespace при этом продолжает гасить
    // копии всех пользователей разом.
    const tracks = await getOrSet(`spotify:playlist-tracks:${playlistId}`, `user:${userId}`, CACHE_TTL.playlistTracks, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const collected = [];
      let nextUrl =
        `https://api.spotify.com/v1/playlists/${encodeURIComponent(playlistId)}/items?limit=50`;

      while (nextUrl && collected.length < 1000) {
        const page = await spotifyGet(spotifyUser, nextUrl);
        collected.push(...(page.items || []));
        nextUrl = page.next;
      }

      const data = { items: collected };

      return (data.items || [])
        .map((item) => extractTrack(item))
        .filter((track) => track !== null && track.id)
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
    return handleSpotifyError(res, error, { userId, playlistId, route: '/playlists/:id/tracks' });
  }
}));

router.get('/status', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const status = await getOrSet(`spotify:status:${userId}`, 'status', CACHE_TTL.status, async () => {
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
    return handleSpotifyError(res, error, { userId, route: '/status' });
  }
}));

router.get('/devices', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const devices = await getOrSet(`spotify:devices:${userId}`, 'list', CACHE_TTL.devices, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const data = await spotifyGet(spotifyUser, 'https://api.spotify.com/v1/me/player/devices');
      return data.devices;
    });

    res.json(devices);
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/devices' });
  }
}));

router.get('/player', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    const response = await spotifyRequest(spotifyUser, {
      method: 'get',
      url: 'https://api.spotify.com/v1/me/player',
    });
    if (response.status === 204 || !response.data) return res.json(null);
    res.json(response.data);
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/player' });
  }
}));


router.post('/play', rateLimitMiddleware(15, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { uri, deviceId, contextUri, offset } = playBodySchema.parse(req.body);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    const playUrl = deviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${encodeURIComponent(deviceId)}`
      : 'https://api.spotify.com/v1/me/player/play';

    const body = contextUri
      ? { context_uri: contextUri, ...(offset !== undefined && { offset: { position: offset } }) }
      : { uris: [uri] };

    await spotifyRequest(spotifyUser, { method: 'put', url: playUrl, data: body });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/play' });
  }
}));

router.put('/volume', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { volume_percent } = volumeSchema.parse(req.query);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: `https://api.spotify.com/v1/me/player/volume?volume_percent=${volume_percent}`,
      data: {},
    });
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/volume' });
  }
}));

router.put('/seek', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { position_ms } = seekSchema.parse(req.query);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: `https://api.spotify.com/v1/me/player/seek?position_ms=${position_ms}`,
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/seek' });
  }
}));

router.put('/pause', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: 'https://api.spotify.com/v1/me/player/pause',
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/pause' });
  }
}));

router.put('/resume', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: 'https://api.spotify.com/v1/me/player/play',
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/resume' });
  }
}));

router.post('/next', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'post',
      url: 'https://api.spotify.com/v1/me/player/next',
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/next' });
  }
}));

router.post('/previous', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'post',
      url: 'https://api.spotify.com/v1/me/player/previous',
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/previous' });
  }
}));

router.put('/shuffle', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { state } = shuffleSchema.parse(req.query);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: `https://api.spotify.com/v1/me/player/shuffle?state=${state}`,
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/shuffle' });
  }
}));

router.put('/repeat', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { state } = repeatSchema.parse(req.query);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    await spotifyRequest(spotifyUser, {
      method: 'put',
      url: `https://api.spotify.com/v1/me/player/repeat?state=${state}`,
      data: {},
    });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/repeat' });
  }
}));

router.post('/disconnect', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) return res.status(404).json({ error: 'Spotify не подключен' });

    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: {
        userId: null,
        accessToken: null,
        refreshToken: null,
      },
    });

    await Promise.all([
      incrementVersion(`spotify:status:${userId}`),
      incrementVersion(`spotify:token-info:${userId}`),
      incrementVersion(`spotify:user-playlists:${userId}`),
      incrementVersion(`spotify:devices:${userId}`),
      incrementVersion(`db:user-playlists-db:${userId}`),
      incrementVersion(`db:user-profile:${userId}`),
    ]);

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/disconnect' });
  }
}));

router.get('/token-info', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const info = await getOrSet(`spotify:token-info:${userId}`, 'me', CACHE_TTL.tokenInfo, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const data = await spotifyGet(spotifyUser, 'https://api.spotify.com/v1/me');
      return { spotifyUser: data, hasToken: true };
    });
    res.json(info);
  } catch (error) {
    return handleSpotifyError(res, error, { userId, route: '/token-info' });
  }
}));

module.exports = router;