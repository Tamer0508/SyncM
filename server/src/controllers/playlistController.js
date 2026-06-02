const prisma = require('../db/prisma');
const { getOrSet, invalidateUserDB } = require('../infrastructure/spotify/cache');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

exports.createCustomPlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { name, description, imageUrl } = req.body;
    if (!name || name.trim().length === 0)
      return res.status(400).json({ error: 'Название обязательно' });
    if (name.trim().length > 100)
      return res.status(400).json({ error: 'Название не должно превышать 100 символов' });

    const playlist = await prisma.playlist.create({
      data: {
        userId,
        name: name.trim(),
        description,
        imageUrl,
        isCustom: true,
      },
    });
    await invalidateUserDB(userId);

    res.status(201).json(playlist);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Create custom playlist error:', error);
    }
    res.status(500).json({ error: 'Ошибка создания плейлиста' });
  }
};

exports.getUserPlaylists = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const cacheKey = `db:user-playlists-db:${userId}`;
    const playlists = await getOrSet(cacheKey, null, async () => {
      return await prisma.playlist.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
      });
    });
    res.status(200).json(playlists);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Fetch playlists error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения плейлистов' });
  }
};

exports.toggleLike = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { spotifyUri, trackName, artistName } = req.body;
    if (!spotifyUri) return res.status(400).json({ error: 'spotifyUri обязателен' });

    const existing = await prisma.likedTrack.findUnique({
      where: { userId_spotifyUri: { userId, spotifyUri } },
    });

    if (existing) {
      await prisma.likedTrack.delete({ where: { id: existing.id } });
      await invalidateUserDB(userId);
      return res.json({ liked: false });
    } else {
      await prisma.likedTrack.create({
        data: { userId, spotifyUri, trackName, artistName },
      });
      await invalidateUserDB(userId);
      return res.json({ liked: true });
    }
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Toggle like error:', error);
    }
    res.status(500).json({ error: 'Ошибка лайка' });
  }
};

exports.getLikedTracks = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const cacheKey = `db:liked-tracks:${userId}`;
    const tracks = await getOrSet(cacheKey, null, async () => {
      return await prisma.likedTrack.findMany({
        where: { userId },
        orderBy: { likedAt: 'desc' },
      });
    });
    res.json(tracks);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Get liked tracks error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения избранного' });
  }
};

exports.importPlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { spotifyPlaylistId, name, description, imageUrl } = req.body;
    if (!spotifyPlaylistId) return res.status(400).json({ error: 'spotifyPlaylistId обязателен' });

    let playlist = await prisma.playlist.findFirst({
      where: { userId, spotifyId: spotifyPlaylistId }
    });

    if (playlist) {
      playlist = await prisma.playlist.update({
        where: { id: playlist.id },
        data: { name, description, imageUrl }
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

    await invalidateUserDB(userId);
    res.status(200).json(playlist);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Import playlist error:', error);
    }
    res.status(500).json({ error: 'Ошибка импорта плейлиста' });
  }
};

exports.deletePlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { playlistId } = req.params;
    const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
    if (!playlist) return res.status(404).json({ error: 'Плейлист не найден' });
    if (playlist.userId !== userId)
      return res.status(403).json({ error: 'Нет доступа' });
    if (!playlist.isCustom)
      return res.status(400).json({ error: 'Нельзя удалить импортированный плейлист' });

    await prisma.playlist.delete({ where: { id: playlistId } });
    await invalidateUserDB(userId);
    res.json({ message: 'Плейлист удалён' });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Delete playlist error:', error);
    }
    res.status(500).json({ error: 'Ошибка удаления' });
  }
};

exports.addTrackToPlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { playlistId } = req.params;
    const { trackUri, trackName, artistName, durationMs } = req.body;
    if (!trackUri || !trackName) return res.status(400).json({ error: 'trackUri и trackName обязательны' });

    const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
    if (!playlist || playlist.userId !== userId || !playlist.isCustom)
      return res.status(403).json({ error: 'Нет доступа' });

    const track = await prisma.playlistTrack.create({
      data: {
        playlistId,
        spotifyUri: trackUri,
        trackName,
        artistName: artistName || '',
        durationMs: durationMs || null,
      },
    });
    await invalidateUserDB(userId);
    res.status(201).json(track);
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ error: 'Трек уже есть в этом плейлисте' });
    }
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Add track to playlist error:', error);
    }
    res.status(500).json({ error: 'Ошибка добавления трека' });
  }
};

exports.removeTrackFromPlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { playlistId, trackUri } = req.params;
    const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
    if (!playlist || playlist.userId !== userId || !playlist.isCustom)
      return res.status(403).json({ error: 'Нет доступа' });

    await prisma.playlistTrack.deleteMany({
      where: { playlistId, spotifyUri: trackUri },
    });
    await invalidateUserDB(userId);
    res.json({ message: 'Трек удалён' });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Remove track error:', error);
    }
    res.status(500).json({ error: 'Ошибка удаления трека' });
  }
};

exports.getPlaylistTracks = async (req, res) => {
  try {
    const userId = getUserId(req);
    const { playlistId } = req.params;

    const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
    if (!playlist) return res.status(404).json({ error: 'Плейлист не найден' });

    if (playlist.userId !== userId) {
      if (playlist.isCustom) {
        return res.status(403).json({ error: 'Нет доступа' });
      }
      return res.status(403).json({ error: 'Нет доступа' });
    }

    const cacheKey = `db:playlist-tracks-db:${playlistId}`;
    const tracks = await getOrSet(cacheKey, null, async () => {
      return await prisma.playlistTrack.findMany({
        where: { playlistId },
        orderBy: { addedAt: 'asc' },
      });
    });
    res.json(tracks);
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Get playlist tracks error:', error);
    }
    res.status(500).json({ error: 'Ошибка получения треков' });
  }
};

exports.logPlay = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { spotifyUri, trackName, artistName } = req.body;
    if (!spotifyUri) return res.status(400).json({ error: 'spotifyUri обязателен' });

    await prisma.playHistory.create({
      data: { userId, spotifyUri, trackName, artistName },
    });
    res.status(201).json({ success: true });
  } catch (error) {
    if (req && req.log && typeof req.log.error === 'function') {
      req.log.error('Log play error:', error);
    }
    res.status(500).json({ error: 'Ошибка сохранения истории' });
  }
};
