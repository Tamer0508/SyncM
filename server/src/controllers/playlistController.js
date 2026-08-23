const { t } = require('../infrastructure/i18n');
const { z } = require('zod');
const crypto = require('crypto');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const multer = require('multer');
const prisma = require('../db/prisma');
const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const { withLock } = require('../infrastructure/lock');
const { addPlaylistSyncJob } = require('../infrastructure/queue');
const { backfillArtwork } = require('../infrastructure/spotify/artwork');
const asyncHandler = require('../utils/asyncHandler');
const logger = require('../infrastructure/logger');

const getUserId = (req) => req.userId || req.session?.userId || null;

const COVERS_DIR = path.resolve(__dirname, '../../uploads/covers');

const httpUrlSchema = z.string().url().refine((url) => /^https?:\/\//i.test(url), {
  message: 'Разрешены только http/https ссылки',
});

const createCustomPlaylistSchema = z.object({
  name: z.string().trim().min(1, 'Название обязательно').max(100, 'Название не должно превышать 100 символов'),
  description: z.string().max(500, 'Описание не должно превышать 500 символов').nullable().optional(),
  imageUrl: httpUrlSchema.optional().nullable(),
});

// Отдельная схема для правки, а не переиспользование схемы создания.
//
// У PATCH другая семантика: отсутствующее поле означает «не трогать», тогда
// как явный null у описания и обложки означает «стереть». Схема создания
// такого различия не делает и молча превратила бы «переименовать» в
// «переименовать и заодно снять обложку».
const updatePlaylistSchema = z
  .object({
    name: z.string().trim().min(1, 'Название обязательно').max(100, 'Название не должно превышать 100 символов').optional(),
    description: z.string().max(500, 'Описание не должно превышать 500 символов').nullable().optional(),
    imageUrl: httpUrlSchema.nullable().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: 'Нечего менять',
  });

const toggleLikeSchema = z.object({
  spotifyUri: z.string().min(1, 'spotifyUri обязателен'),
  trackName: z.string().nullable().optional(),
  artistName: z.string().nullable().optional(),
  imageUrl: httpUrlSchema.nullable().optional(),
});

const importPlaylistSchema = z.object({
  spotifyPlaylistId: z.string().min(1, 'spotifyPlaylistId обязателен'),
  name: z.string().nullable().optional(),
  description: z.string().max(500, 'Описание не должно превышать 500 символов').nullable().optional(),
  imageUrl: httpUrlSchema.optional().nullable(),
});

const playlistIdParamsSchema = z.object({
  playlistId: z.string().min(1),
});

const trackUriParamsSchema = z.object({
  trackUri: z.string().min(1),
});

const trackPayloadSchema = z.object({
  trackUri: z.string().min(1, 'trackUri обязателен'),
  trackName: z.string().min(1, 'trackName обязателен'),
  artistName: z.string().nullable().optional().transform((v) => v ?? ''),
  imageUrl: httpUrlSchema.nullable().optional(),
  durationMs: z.number().int().positive().optional().nullable(),
});

const addTrackSchema = trackPayloadSchema;

const addTracksBulkSchema = z.object({
  tracks: z.array(trackPayloadSchema).min(1, 'Список треков пуст').max(200, 'Не более 200 треков за раз'),
});

const reorderSchema = z.object({
  trackUris: z.array(z.string().min(1)).min(1, 'Список порядка пуст').max(1000),
});

const duplicateSchema = z.object({
  name: z.string().trim().min(1).max(100).nullable().optional(),
});

const logPlaySchema = z.object({
  spotifyUri: z.string().min(1, 'spotifyUri обязателен'),
  trackName: z.string().nullable().optional(),
  artistName: z.string().nullable().optional(),
  imageUrl: httpUrlSchema.nullable().optional(),
});

const serializeTrack = (track) => ({
  id: track.id,
  uri: track.spotifyUri,
  name: track.trackName,
  artist: track.artistName,
  imageUrl: track.imageUrl ?? null,
  durationMs: track.durationMs ?? null,
  position: track.position,
  addedAt: track.addedAt,
});

const serializePlaylist = (playlist) => ({
  id: playlist.id,
  name: playlist.name,
  description: playlist.description,
  imageUrl: playlist.imageUrl,
  isCustom: playlist.isCustom,
  spotifyId: playlist.spotifyId,
  trackCount: playlist._count?.playlistTracks ?? playlist.trackCount ?? 0,
  createdAt: playlist.createdAt,
  updatedAt: playlist.updatedAt,
});

async function requireEditablePlaylist(playlistId, userId) {
  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist) return { error: { status: 404, message: 'Плейлист не найден' } };
  if (playlist.userId !== userId) return { error: { status: 403, message: 'Нет доступа' } };
  if (!playlist.isCustom) {
    return { error: { status: 400, message: 'Импортированный плейлист нельзя изменить' } };
  }
  return { playlist };
}

const invalidatePlaylistTracks = (userId, playlistId) =>
  Promise.all([
    incrementVersion(`db:playlist-tracks-db:${playlistId}`),
    incrementVersion(`db:user-playlists-db:${userId}`),
  ]);

const createCustomPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

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

  await incrementVersion(`db:user-playlists-db:${userId}`);
  res.status(201).json(serializePlaylist({ ...playlist, trackCount: 0 }));
});

const getUserPlaylists = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const playlists = await getOrSet(`db:user-playlists-db:${userId}`, 'list-v2', 120, async () => {
    const rows = await prisma.playlist.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      include: { _count: { select: { playlistTracks: true } } },
    });
    return rows.map(serializePlaylist);
  });

  res.status(200).json(playlists);
});

const updatePlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const patch = updatePlaylistSchema.parse(req.body);

  const { playlist, error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  const previousImage = playlist.imageUrl;

  const updated = await prisma.playlist.update({
    where: { id: playlistId },
    data: patch,
    include: { _count: { select: { playlistTracks: true } } },
  });

  if ('imageUrl' in patch && patch.imageUrl !== previousImage) {
    await safeDeleteCover(previousImage);
  }

  await incrementVersion(`db:user-playlists-db:${userId}`);
  res.json(serializePlaylist(updated));
});

const toggleLike = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { spotifyUri, trackName, artistName, imageUrl } = toggleLikeSchema.parse(req.body);

  const existing = await prisma.likedTrack.findUnique({
    where: { userId_spotifyUri: { userId, spotifyUri } },
  });

  if (existing) {
    await prisma.likedTrack.delete({ where: { id: existing.id } });
    await incrementVersion(`db:liked-tracks:${userId}`);
    return res.json({ liked: false });
  } else {
    await prisma.likedTrack.create({
      data: { userId, spotifyUri, trackName, artistName, imageUrl },
    });
    await incrementVersion(`db:liked-tracks:${userId}`);
    return res.json({ liked: true });
  }
});

const getLikedTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const tracks = await getOrSet(`db:liked-tracks:${userId}`, 'list-v2', 120, async () => {
    const rows = await prisma.likedTrack.findMany({
      where: { userId },
      orderBy: { likedAt: 'desc' },
    });
    return backfillArtwork(userId, rows, 'likedTrack');
  });

  res.json(tracks);
});

const importPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { spotifyPlaylistId, name, description, imageUrl } = importPlaylistSchema.parse(req.body);

  const playlist = await withLock(`playlist-import:${userId}:${spotifyPlaylistId}`, 5000, async () => {
    const existing = await prisma.playlist.findFirst({
      where: { userId, spotifyId: spotifyPlaylistId },
    });

    if (existing) {
      return prisma.playlist.update({
        where: { id: existing.id },
        data: { name, description, imageUrl },
      });
    }

    return prisma.playlist.create({
      data: {
        userId,
        spotifyId: spotifyPlaylistId,
        name,
        description,
        imageUrl,
        isCustom: false,
      },
    });
  });

  await incrementVersion(`db:user-playlists-db:${userId}`);

  await addPlaylistSyncJob({ userId, playlistId: spotifyPlaylistId, fullSync: true }).catch((err) => {
    logger.error({ err, userId, spotifyPlaylistId }, 'Failed to enqueue playlist sync after import');
  });

  res.status(200).json(playlist);
});

const duplicatePlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { name } = duplicateSchema.parse(req.body ?? {});

  const source = await prisma.playlist.findUnique({
    where: { id: playlistId },
    include: { playlistTracks: { orderBy: [{ position: 'asc' }, { addedAt: 'asc' }] } },
  });
  if (!source) return res.status(404).json({ error: t(req, 'playlistNotFound') });
  if (source.userId !== userId) return res.status(403).json({ error: t(req, 'forbidden') });

  const copyName = (name ?? `${source.name} — копия`).slice(0, 100);

  const created = await prisma.$transaction(async (tx) => {
    const playlist = await tx.playlist.create({
      data: {
        userId,
        name: copyName,
        description: source.description,
        imageUrl: source.imageUrl,
        isCustom: true,
      },
    });

    if (source.playlistTracks.length > 0) {
      await tx.playlistTrack.createMany({
        data: source.playlistTracks.map((track, index) => ({
          playlistId: playlist.id,
          spotifyUri: track.spotifyUri,
          trackName: track.trackName,
          artistName: track.artistName,
          imageUrl: track.imageUrl,
          durationMs: track.durationMs,
          position: index,
        })),
      });
    }

    return playlist;
  });

  await incrementVersion(`db:user-playlists-db:${userId}`);
  res.status(201).json(serializePlaylist({ ...created, trackCount: source.playlistTracks.length }));
});

const deletePlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist) return res.status(404).json({ error: t(req, 'playlistNotFound') });
  if (playlist.userId !== userId) return res.status(403).json({ error: t(req, 'forbidden') });
  if (!playlist.isCustom) return res.status(400).json({ error: t(req, 'playlistImported') });

  await prisma.playlist.delete({ where: { id: playlistId } });
  await safeDeleteCover(playlist.imageUrl);
  await invalidatePlaylistTracks(userId, playlistId);

  res.json({ message: 'Плейлист удалён' });
});

const nextPosition = async (playlistId) => {
  const last = await prisma.playlistTrack.findFirst({
    where: { playlistId },
    orderBy: { position: 'desc' },
    select: { position: true },
  });
  return last ? last.position + 1 : 0;
};

const addTrackToPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { trackUri, trackName, artistName, imageUrl, durationMs } = addTrackSchema.parse(req.body);

  const { error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  let track;
  try {
    track = await prisma.playlistTrack.create({
      data: {
        playlistId,
        spotifyUri: trackUri,
        trackName,
        artistName,
        imageUrl,
        durationMs,
        position: await nextPosition(playlistId),
      },
    });
  } catch (err) {
    if (err.code === 'P2002') {
      return res.status(409).json({ error: t(req, 'trackAlreadyInPlaylist') });
    }
    throw err; // пробрасываем остальные ошибки
  }

  await invalidatePlaylistTracks(userId, playlistId);
  res.status(201).json(serializeTrack(track));
});

const addTracksBulk = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { tracks } = addTracksBulkSchema.parse(req.body);

  const { error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  const result = await withLock(`playlist-add-tracks:${playlistId}`, 10000, async () => {
    const existing = await prisma.playlistTrack.findMany({
      where: { playlistId },
      select: { spotifyUri: true },
    });
    const known = new Set(existing.map((t) => t.spotifyUri));

    const fresh = [];
    for (const track of tracks) {
      if (known.has(track.trackUri)) continue;
      known.add(track.trackUri);
      fresh.push(track);
    }

    if (fresh.length === 0) return { added: 0, skipped: tracks.length };

    const start = await nextPosition(playlistId);
    await prisma.playlistTrack.createMany({
      data: fresh.map((track, index) => ({
        playlistId,
        spotifyUri: track.trackUri,
        trackName: track.trackName,
        artistName: track.artistName,
        imageUrl: track.imageUrl,
        durationMs: track.durationMs,
        position: start + index,
      })),
      skipDuplicates: true,
    });

    return { added: fresh.length, skipped: tracks.length - fresh.length };
  }, { failOpen: true });

  if (result.added > 0) await invalidatePlaylistTracks(userId, playlistId);
  res.status(200).json(result);
});

const reorderTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { trackUris } = reorderSchema.parse(req.body);

  const { error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  await withLock(`playlist-reorder:${playlistId}`, 10000, async () => {
    const existing = await prisma.playlistTrack.findMany({
      where: { playlistId },
      orderBy: [{ position: 'asc' }, { addedAt: 'asc' }],
      select: { id: true, spotifyUri: true },
    });

    const byUri = new Map(existing.map((t) => [t.spotifyUri, t.id]));

    const orderedIds = [];
    const seen = new Set();
    for (const uri of trackUris) {
      const id = byUri.get(uri);
      if (id && !seen.has(id)) {
        seen.add(id);
        orderedIds.push(id);
      }
    }
    for (const track of existing) {
      if (!seen.has(track.id)) orderedIds.push(track.id);
    }

    await prisma.$transaction(
      orderedIds.map((id, index) =>
        prisma.playlistTrack.update({ where: { id }, data: { position: index } })
      )
    );
  }, { failOpen: true });

  await invalidatePlaylistTracks(userId, playlistId);
  res.json({ message: 'Порядок сохранён' });
});

const removeTrackFromPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { trackUri } = trackUriParamsSchema.parse(req.params);

  const { error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  const { count } = await prisma.playlistTrack.deleteMany({
    where: { playlistId, spotifyUri: trackUri },
  });

  if (count > 0) {
    await invalidatePlaylistTracks(userId, playlistId);
  }

  res.json({ message: 'Трек удалён', removed: count });
});

const clearPlaylist = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  const { error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  const { count } = await prisma.playlistTrack.deleteMany({ where: { playlistId } });
  if (count > 0) await invalidatePlaylistTracks(userId, playlistId);

  res.json({ message: 'Плейлист очищен', removed: count });
});

const getPlaylistTracks = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);

  const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
  if (!playlist) return res.status(404).json({ error: t(req, 'playlistNotFound') });

  if (playlist.userId !== userId) {
    return res.status(403).json({ error: t(req, 'playlistNoAccess') });
  }

  const tracks = await getOrSet(`db:playlist-tracks-db:${playlistId}`, 'list-v2', 120, async () => {
    const rows = await prisma.playlistTrack.findMany({
      where: { playlistId },
      orderBy: [{ position: 'asc' }, { addedAt: 'asc' }],
    });
    return rows.map(serializeTrack);
  });

  res.json(tracks);
});

const logPlay = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { spotifyUri, trackName, artistName, imageUrl } = logPlaySchema.parse(req.body);

  await prisma.playHistory.create({
    data: { userId, spotifyUri, trackName, artistName, imageUrl },
  });

  res.status(201).json({ success: true });
});


const ALLOWED_COVER_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp']);

function resolveCoverExt(file) {
  const ext = path.extname(file.originalname || '').toLowerCase();
  if (ALLOWED_COVER_EXT.has(ext)) return ext === '.jpeg' ? '.jpg' : ext;
  return null;
}

const coverStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    fs.mkdir(COVERS_DIR, { recursive: true }, (err) => cb(err, COVERS_DIR));
  },
  filename: (req, file, cb) => {
    const ext = resolveCoverExt(file) || '.png';
    const owner = getUserId(req) || 'user';
    cb(null, `${owner}_${Date.now()}_${crypto.randomBytes(6).toString('hex')}${ext}`);
  },
});

const coverUpload = multer({
  storage: coverStorage,
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    if (resolveCoverExt(file)) return cb(null, true);
    cb(new Error('Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP'), false);
  },
}).single('cover');

async function safeDeleteCover(coverUrl, currentFilename) {
  if (!coverUrl) return;
  try {
    const parsed = new URL(coverUrl);
    if (!parsed.pathname.startsWith('/uploads/covers/')) return;

    const name = path.basename(parsed.pathname);
    if (!name || name === currentFilename) return;

    const resolved = path.resolve(COVERS_DIR, name);
    if (resolved !== path.join(COVERS_DIR, name)) return;
    if (!resolved.startsWith(COVERS_DIR + path.sep)) return;

    await fsp.unlink(resolved);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      logger.warn({ err, coverUrl }, 'Could not delete old playlist cover');
    }
  }
}

const uploadCover = (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  coverUpload(req, res, async (err) => {
    if (err) {
      const message = err.message?.includes('Неподдерживаемый формат')
        ? err.message
        : `Ошибка загрузки файла: ${err.message}`;
      return res.status(400).json({ error: message });
    }
    if (!req.file) {
      return res.status(400).json({
        error: t(req, 'fileNotChosen'),
      });
    }

    const cleanup = () => fsp.unlink(req.file.path).catch(() => {});

    try {
      const { playlistId } = playlistIdParamsSchema.parse(req.params);
      const { playlist, error: accessError } = await requireEditablePlaylist(playlistId, userId);
      if (accessError) {
        await cleanup();
        return res.status(accessError.status).json({ error: accessError.message });
      }

      const baseUrl = process.env.BASE_URL || `https://${req.get('host')}`;
      const imageUrl = `${baseUrl}/uploads/covers/${req.file.filename}`;

      const updated = await prisma.playlist.update({
        where: { id: playlistId },
        data: { imageUrl },
        include: { _count: { select: { playlistTracks: true } } },
      });

      await safeDeleteCover(playlist.imageUrl, req.file.filename);
      await incrementVersion(`db:user-playlists-db:${userId}`);

      res.json(serializePlaylist(updated));
    } catch (error) {
      logger.error({ err: error, userId }, 'Upload playlist cover error');
      // Не оставляем осиротевший файл, если запись в БД не удалась.
      await cleanup();
      res.status(500).json({ error: t(req, 'coverSaveFailed') });
    }
  });
};

const deleteCover = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { playlistId } = playlistIdParamsSchema.parse(req.params);
  const { playlist, error } = await requireEditablePlaylist(playlistId, userId);
  if (error) return res.status(error.status).json({ error: error.message });

  const updated = await prisma.playlist.update({
    where: { id: playlistId },
    data: { imageUrl: null },
    include: { _count: { select: { playlistTracks: true } } },
  });

  await safeDeleteCover(playlist.imageUrl);
  await incrementVersion(`db:user-playlists-db:${userId}`);

  res.json(serializePlaylist(updated));
});

module.exports = {
  createCustomPlaylist,
  getUserPlaylists,
  updatePlaylist,
  duplicatePlaylist,
  toggleLike,
  getLikedTracks,
  importPlaylist,
  deletePlaylist,
  addTrackToPlaylist,
  addTracksBulk,
  reorderTracks,
  removeTrackFromPlaylist,
  clearPlaylist,
  getPlaylistTracks,
  uploadCover,
  deleteCover,
  logPlay,
};
