const prisma = require('../db/prisma');

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

    const playlist = await prisma.playlist.create({
      data: {
        userId,
        name: name.trim(),
        description,
        imageUrl,
        isCustom: true,
      },
    });

    res.status(201).json(playlist);
  } catch (error) {
    console.error('Create custom playlist error:', error);
    res.status(500).json({ error: 'Ошибка создания плейлиста' });
  }
};

exports.getUserPlaylists = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const playlists = await prisma.playlist.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    res.status(200).json(playlists);
  } catch (error) {
    console.error('Fetch playlists error:', error);
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
      return res.json({ liked: false });
    } else {
      await prisma.likedTrack.create({
        data: { userId, spotifyUri, trackName, artistName },
      });
      return res.json({ liked: true });
    }
  } catch (error) {
    console.error('Toggle like error:', error);
    res.status(500).json({ error: 'Ошибка лайка' });
  }
};

exports.getLikedTracks = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const tracks = await prisma.likedTrack.findMany({
      where: { userId },
      orderBy: { likedAt: 'desc' },
    });
    res.json(tracks);
  } catch (error) {
    console.error('Get liked tracks error:', error);
    res.status(500).json({ error: 'Ошибка получения избранного' });
  }
};

exports.importPlaylist = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const { spotifyPlaylistId, name, description, imageUrl } = req.body;
    if (!spotifyPlaylistId) return res.status(400).json({ error: 'spotifyPlaylistId обязателен' });

    const playlist = await prisma.playlist.upsert({
      where: { spotifyId: spotifyPlaylistId },
      update: { name, description, imageUrl },
      create: {
        userId,
        spotifyId: spotifyPlaylistId,
        name,
        description,
        imageUrl,
        isCustom: false,
      },
    });

    res.status(200).json(playlist);
  } catch (error) {
    console.error('Import playlist error:', error);
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
    if (playlist.userId !== userId || !playlist.isCustom)
      return res.status(403).json({ error: 'Нет доступа' });

    await prisma.playlist.delete({ where: { id: playlistId } });
    res.json({ message: 'Плейлист удалён' });
  } catch (error) {
    console.error('Delete playlist error:', error);
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
    res.status(201).json(track);
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ error: 'Трек уже есть в этом плейлисте' });
    }
    console.error('Add track to playlist error:', error);
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
    res.json({ message: 'Трек удалён' });
  } catch (error) {
    console.error('Remove track error:', error);
    res.status(500).json({ error: 'Ошибка удаления трека' });
  }
};

exports.getPlaylistTracks = async (req, res) => {
  try {
    const userId = getUserId(req);
    const { playlistId } = req.params;

    const playlist = await prisma.playlist.findUnique({ where: { id: playlistId } });
    if (!playlist) return res.status(404).json({ error: 'Плейлист не найден' });

    if (playlist.isCustom || playlist.userId === userId) {
      const tracks = await prisma.playlistTrack.findMany({
        where: { playlistId },
        orderBy: { addedAt: 'asc' },
      });
      return res.json(tracks);
    }

    return res.json([]);
  } catch (error) {
    console.error('Get playlist tracks error:', error);
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
    console.error('Log play error:', error);
    res.status(500).json({ error: 'Ошибка сохранения истории' });
  }
};
