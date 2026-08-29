const { t } = require('../infrastructure/i18n');
const express = require('express');
const router = express.Router();
const { z } = require('zod');
const requireAuth = require('../middleware/requireAuth');
router.use(requireAuth);
const prisma = require('../db/prisma');
const { getOrSet, getVersioned, setVersioned, incrementVersion } = require('../infrastructure/redis');
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
const { collectAllPages, withPaging, DEFAULT_PAGE_SIZE } = require('../infrastructure/spotify/paging');
const { isPlaylistUsableForCurrentUser } = require('../infrastructure/spotify/playlists');

const getUserId = (req) => req.userId || req.session?.userId || null;

const extractTrack = (item) => item?.item || item?.track || null;

const mapTrack = (track) => ({
  id: track.id,
  name: track.name,
  artist: track.artists?.map((a) => a.name).join(', ') ?? '',
  imageUrl: track.album?.images?.[0]?.url || null,
  uri: track.uri,
  durationMs: track.duration_ms,
  album: track.album?.name ?? '',
});

const isPlayableTrack = (track) =>
  Boolean(track) &&
  typeof track.id === 'string' &&
  track.id.length > 0 &&
  typeof track.uri === 'string' &&
  track.uri.startsWith('spotify:track:') &&
  track.is_local !== true;

const CACHE_TTL = {
  userPlaylists: 600,
  playlistTracks: 1800,
  savedTracks: 300,
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

const searchQuerySchema = z.object({
  q: z.string().trim().min(1, 'Пустой запрос').max(100),
});

const playBodySchema = z
  .object({
    uri: z.string().min(1).optional(),
    deviceId: z.string().min(1).optional(),
    contextUri: z.string().min(1).optional(),
    offset: z.number().int().min(0).optional(),
    offsetUri: z.string().min(1).optional(),
  })
  .refine((b) => b.uri || b.contextUri, {
    message: 'Требуется uri или contextUri',
  });

function handleSpotifyError(req, res, error, context) {
  if (error instanceof SpotifyNotConnectedError) {
    return res.status(409).json({ error: t(req, 'spotifyNotConnected') });
  }
  if (error instanceof SpotifyApiError) {
    logger.warn({ err: error, status: error.status, ...context }, 'Spotify API error');
    if (error.status === 404) {
      return res.status(409).json({ error: t(req, 'spotifyNoDevice') });
    }
    if (error.status === 403) {
      return res.status(403).json({ error: t(req, 'spotifyPremiumRequired') });
    }
    if (error.status === 429) {
      return res.status(429).json({ error: t(req, 'spotifyRateLimited') });
    }
    return res.status(502).json({ error: t(req, 'spotifyApiError') });
  }
  logger.error({ err: error, ...context }, 'Unexpected Spotify route error');
  return res.status(500).json({ error: t(req, 'internalError') });
}

async function requireSpotifyUser(userId) {
  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) throw new SpotifyNotConnectedError();
  return spotifyUser;
}

const invalidatePlaybackCaches = (userId) => incrementVersion(`spotify:devices:${userId}`);

router.get('/playlists', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const playlists = await getOrSet(`spotify:user-playlists:${userId}`, 'list:v2', CACHE_TTL.userPlaylists, async () => {
      const spotifyUser = await requireSpotifyUser(userId);

      const all = await collectAllPages(
        (offset, limit) =>
          spotifyGet(
            spotifyUser,
            withPaging('https://api.spotify.com/v1/me/playlists', offset, limit)
          ),
        { maxItems: 500 }
      );

      return all
        .filter((p) =>
          isPlaylistUsableForCurrentUser(p, {
            currentSpotifyId: spotifyUser.spotifyId,
            capability: 'read',
          })
        )
        .map((p) => ({
          id: p.id,
          name: p.name,
          description: p.description,
          imageUrl: p.images?.[0]?.url || null,
          trackCount: p.items?.total ?? p.tracks?.total ?? 0,
          owner: p.owner?.display_name,
          isPublic: p.public,
        }));
    });

    res.json(playlists);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/playlists' });
  }
}));

router.get('/playlists/:playlistId/tracks', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  try {
    const tracks = await getOrSet(`spotify:playlist-tracks:${playlistId}`, `user:${userId}:v2`, CACHE_TTL.playlistTracks, async () => {
      const spotifyUser = await requireSpotifyUser(userId);

      const itemsUrl =
        `https://api.spotify.com/v1/playlists/${encodeURIComponent(playlistId)}/items`;

      const collected = await collectAllPages(
        (offset, limit) => spotifyGet(spotifyUser, withPaging(itemsUrl, offset, limit)),
        { maxItems: 1000 }
      );

      return collected
        .map((item, contextIndex) => ({ track: extractTrack(item), contextIndex }))
        .filter(({ track }) => isPlayableTrack(track))
        .map(({ track, contextIndex }) => ({ ...mapTrack(track), contextIndex }));
    });

    res.json(tracks);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, playlistId, route: '/playlists/:id/tracks' });
  }
}));

router.get('/saved-tracks', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const tracks = await getOrSet(`spotify:saved-tracks:${userId}`, 'list', CACHE_TTL.savedTracks, async () => {
      const spotifyUser = await requireSpotifyUser(userId);

      const collected = await collectAllPages(
        (offset, limit) =>
          spotifyGet(
            spotifyUser,
            withPaging('https://api.spotify.com/v1/me/tracks', offset, limit)
          ),
        { maxItems: 1000 }
      );

      return collected
        .map((item) => extractTrack(item))
        .filter((track) => isPlayableTrack(track))
        .map(mapTrack);
    });

    res.json(tracks);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/saved-tracks' });
  }
}));

router.get('/search', rateLimitMiddleware(40, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { q } = searchQuerySchema.parse(req.query);

  try {
    const spotifyUser = await requireSpotifyUser(userId);

    const target = new URL('https://api.spotify.com/v1/search');
    target.searchParams.set('q', q);
    target.searchParams.set('type', 'track');

    const data = await spotifyGet(
      spotifyUser,
      withPaging(target.toString(), 0, DEFAULT_PAGE_SIZE)
    );

    const tracks = (data?.tracks?.items ?? [])
      .filter((track) => isPlayableTrack(track))
      .map(mapTrack);

    res.json(tracks);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/search' });
  }
}));

const SPOTIFY_STATE = {
  disconnected: 'disconnected',
  connected: 'connected',
  needsReauth: 'needs_reauth',
};

const STATUS_TTL = { ok: CACHE_TTL.status, failed: 30 };

function isAuthFailure(error) {
  if (error instanceof SpotifyNotConnectedError) return true;
  if (error instanceof SpotifyApiError) return error.status === 401 || error.status === 403;

  return error?.response?.data?.error === 'invalid_grant';
}

router.get('/status', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const namespace = `spotify:status:${userId}`;
  const cached = await getVersioned(namespace, 'status:v2');
  if (cached !== null) return res.json(cached);

  const spotifyUser = await getSpotifyUser(userId);

  if (!spotifyUser) {
    const status = {
      connected: false,
      state: SPOTIFY_STATE.disconnected,
      spotifyId: null,
      displayName: null,
      avatarUrl: null,
    };
    await setVersioned(namespace, 'status:v2', status, STATUS_TTL.ok);
    return res.json(status);
  }

  const identity = {
    spotifyId: spotifyUser.spotifyId,
    displayName: spotifyUser.displayName,
    avatarUrl: spotifyUser.avatarUrl,
  };

  if (!spotifyUser.accessToken || !spotifyUser.refreshToken) {
    const status = { connected: false, state: SPOTIFY_STATE.needsReauth, ...identity };
    await setVersioned(namespace, 'status:v2', status, STATUS_TTL.failed);
    return res.json(status);
  }

  try {
    await spotifyGet(spotifyUser, 'https://api.spotify.com/v1/me');
    const status = { connected: true, state: SPOTIFY_STATE.connected, ...identity };
    await setVersioned(namespace, 'status:v2', status, STATUS_TTL.ok);
    return res.json(status);
  } catch (error) {
    if (isAuthFailure(error)) {
      logger.info({ userId }, 'Spotify access revoked or expired beyond refresh');
      const status = { connected: false, state: SPOTIFY_STATE.needsReauth, ...identity };
      await setVersioned(namespace, 'status:v2', status, STATUS_TTL.failed);
      return res.json(status);
    }

    logger.warn({ err: error, userId }, 'Spotify status probe failed, reporting last known state');
    return res.json({ connected: true, state: SPOTIFY_STATE.connected, stale: true, ...identity });
  }
}));

router.get('/devices', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const devices = await getOrSet(`spotify:devices:${userId}`, 'list', CACHE_TTL.devices, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const data = await spotifyGet(spotifyUser, 'https://api.spotify.com/v1/me/player/devices');
      return data.devices;
    });

    res.json(devices);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/devices' });
  }
}));

router.get('/player', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    const response = await spotifyRequest(spotifyUser, {
      method: 'get',
      url: 'https://api.spotify.com/v1/me/player',
    });
    if (response.status === 204 || !response.data) return res.json(null);
    res.json(response.data);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/player' });
  }
}));


router.post('/play', rateLimitMiddleware(15, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { uri, deviceId, contextUri, offset, offsetUri } = playBodySchema.parse(req.body);

  try {
    const spotifyUser = await requireSpotifyUser(userId);
    const playUrl = deviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${encodeURIComponent(deviceId)}`
      : 'https://api.spotify.com/v1/me/player/play';

    const contextOffset = offsetUri
      ? { offset: { uri: offsetUri } }
      : offset !== undefined
        ? { offset: { position: offset } }
        : {};

    const body = contextUri
      ? { context_uri: contextUri, ...contextOffset }
      : { uris: [uri] };

    await spotifyRequest(spotifyUser, { method: 'put', url: playUrl, data: body });
    await invalidatePlaybackCaches(userId);
    return res.json({ success: true });
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/play' });
  }
}));

router.put('/volume', rateLimitMiddleware(30, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/volume' });
  }
}));

router.put('/seek', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/seek' });
  }
}));

router.put('/pause', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/pause' });
  }
}));

router.put('/resume', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/resume' });
  }
}));

router.post('/next', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/next' });
  }
}));

router.post('/previous', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/previous' });
  }
}));

router.put('/shuffle', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/shuffle' });
  }
}));

router.put('/repeat', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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
    return handleSpotifyError(req, res, error, { userId, route: '/repeat' });
  }
}));

router.post('/disconnect', rateLimitMiddleware(10, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const spotifyUser = await getSpotifyUser(userId);
    if (!spotifyUser) {
      return res.status(404).json({ error: t(req, 'spotifyNotConnected') });
    }

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
      incrementVersion(`spotify:saved-tracks:${userId}`),
      incrementVersion(`spotify:devices:${userId}`),
      incrementVersion(`db:user-playlists-db:${userId}`),
      incrementVersion(`db:user-profile:${userId}`),
    ]);

    res.json({ message: 'Spotify успешно отключен' });
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/disconnect' });
  }
}));

router.get('/token-info', rateLimitMiddleware(20, 60), asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  try {
    const info = await getOrSet(`spotify:token-info:${userId}`, 'me', CACHE_TTL.tokenInfo, async () => {
      const spotifyUser = await requireSpotifyUser(userId);
      const data = await spotifyGet(spotifyUser, 'https://api.spotify.com/v1/me');
      return { spotifyUser: data, hasToken: true };
    });
    res.json(info);
  } catch (error) {
    return handleSpotifyError(req, res, error, { userId, route: '/token-info' });
  }
}));

module.exports = router;