const { z } = require('zod');
const prisma = require('../db/prisma');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const asyncHandler = require('../utils/asyncHandler');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const createCustomPlaylistSchema = z.object({
  name: z.string().trim().min(1, 'Название обязательно').max(100, 'Название не должно превышать 100 символов'),
  description: z.string().optional(),
  imageUrl: z.string().url().optional().nullable(),
});

const toggleLikeSchema = z.object({
  spotifyUri: z.string().min(1, 'spotifyUri обязателен'),
  trackName: z.string().optional(),
  artistName: z.string().optional(),
});

const importPlaylistSchema = z.object({
  spotifyPlaylistId: z.string().min(1, 'spotifyPlaylistId обязателен'),
  name: z.string().optional(),
  description: z.string().optional(),
  imageUrl: z.string().url().optional().nullable(),
});

const playlistIdParamsSchema = z.object({
  playlistId: z.string().min(1),
});

const addTrackSchema = z.object({
  trackUri: z.string().min(1, 'trackUri обязателен'),
  trackName: z.string().min(1, 'trackName обязателен'),
  artistName: z.string().optional().default(''),
  durationMs: z.number().int().positive().optional().nullable(),
});

const logPlaySchema = z.object({
  spotifyUri: z.string().min(1, 'spotifyUri обязателен'),
  trackName: z.string().optional(),
  artistName: z.string().optional(),
});


const createCustomPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { name, description, imageUrl } = createCustomPlaylistSchema.parse(req.body);

  const playlist = await prisma.playlist.create({
    data: {
      userId,
      name,
      description,
      imageUrl,
      isCustom: true,
    },
  });

  await incrementVersion(); // инвалидация кэша
  res.status(201).json(playlist);
});

const getUserPlaylists = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:user-playlists-db:${userId}`;
  const playlists = await getOrSet(cacheKey, 120, async () => {
    return prisma.playlist.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  });

  res.status(200).json(playlists);
});

const toggleLike = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { spotifyUri, trackName, artistName } = toggleLikeSchema.parse(req.body);

  const existing = await prisma.likedTrack.findUnique({
    where: { userId_spotifyUri: { userId, spotifyUri } },
  });

  if (existing) {
    await prisma.likedTrack.delete({ where: { id: existing.id } });
    await incrementVersion();
    return res.json({ liked: false });
  } else {
    await prisma.likedTrack.create({
      data: { userId, spotifyUri, trackName, artistName },
    });
    await incrementVersion();
    return res.json({ liked: true });
  }
});

const getLikedTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:liked-tracks:${userId}`;
  const tracks = await getOrSet(cacheKey, 120, async () => {
    return prisma.likedTrack.findMany({
      where: { userId },
      orderBy: { likedAt: 'desc' },
    });
  });

  res.json(tracks);
});

const importPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { spotifyPlaylistId, name, description, imageUrl } = importPlaylistSchema.parse(req.body);

  let playlist = await prisma.playlist.findFirst({
    where: { userId, spotifyId: spotifyPlaylistId },
  });

  if (playlist) {
    playlist = await prisma.playlist.update({
      where: { id: playlist.id },
      data: { name, description, imageUrl },
    });
  } else {
    playlist = await prisma.playlist.create({
      data: {
        userId,
        spotifyId: spotifyPlaylistId,
        name,
        description,
        imageUrl,
        isCustom: false,
      },
    });
  }

  await incrementVersion();
  res.status(200).json(playlist);
});

const deletePlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist) return res.status(404).json({ error: 'Плейлист не найден' });
  if (playlist.userId !== userId) return res.status(403).json({ error: 'Нет доступа' });
  if (!playlist.isCustom) return res.status(400).json({ error: 'Нельзя удалить импортированный плейлист' });

  await prisma.playlist.delete({ where: { id: playlistId } });
  await incrementVersion();

  res.json({ message: 'Плейлист удалён' });
});

const addTrackToPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { trackUri, trackName, artistName, durationMs } = addTrackSchema.parse(req.body);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist || playlist.userId !== userId || !playlist.isCustom) {
    return res.status(403).json({ error: 'Нет доступа' });
  }

  let track;
  try {
    track = await prisma.playlistTrack.create({
      data: {
        playlistId,
        spotifyUri: trackUri,
        trackName,
        artistName,
        durationMs,
      },
    });
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ error: 'Трек уже есть в этом плейлисте' });
    }
    throw error; // пробрасываем остальные ошибки
  }

  await incrementVersion();
  res.status(201).json(track);
});

const removeTrackFromPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  // Для trackUri используется отдельный параметр, но он приходит в маршруте как :trackUri?
  // Проверим текущий роутер. Предположим, он передаётся в req.params.trackUri.
  // Добавим схему для trackUri.
  const trackUriSchema = z.object({ trackUri: z.string().min(1) });
  const { trackUri } = trackUriSchema.parse(req.params);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist || playlist.userId !== userId || !playlist.isCustom) {
    return res.status(403).json({ error: 'Нет доступа' });
  }

  await prisma.playlistTrack.deleteMany({
    where: { playlistId, spotifyUri: trackUri },
  });

  await incrementVersion();
  res.json({ message: 'Трек удалён' });
});

const getPlaylistTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist) return res.status(404).json({ error: 'Плейлист не найден' });

  // Проверка доступа: свой плейлист или публичный импортированный?
  if (playlist.userId !== userId) {
    if (playlist.isCustom) return res.status(403).json({ error: 'Нет доступа' });
    // для импортированных можно разрешить только публичные, но в старой логике было 403
    return res.status(403).json({ error: 'Нет доступа' });
  }

  const cacheKey = `db:playlist-tracks-db:${playlistId}`;
  const tracks = await getOrSet(cacheKey, 120, async () => {
    return prisma.playlistTrack.findMany({
      where: { playlistId },
      orderBy: { addedAt: 'asc' },
    });
  });

  res.json(tracks);
});

const logPlay = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { spotifyUri, trackName, artistName } = logPlaySchema.parse(req.body);

  await prisma.playHistory.create({
    data: { userId, spotifyUri, trackName, artistName },
  });

  // await incrementVersion(); // опционально
  res.status(201).json({ success: true });
});

module.exports = {
  createCustomPlaylist,
  getUserPlaylists,
  toggleLike,
  getLikedTracks,
  importPlaylist,
  deletePlaylist,
  addTrackToPlaylist,
  removeTrackFromPlaylist,
  getPlaylistTracks,
  logPlay,
};