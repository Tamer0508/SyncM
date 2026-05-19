const prisma = require('../db/prisma');
const axios = require('axios');

// Импорт плейлиста из Spotify в нашу БД
exports.importPlaylist = async (req, res) => {
  try {
    const { spotifyPlaylistId, name, description, imageUrl } = req.body;
    const userId = req.user.id; // Предполагаем, что userId берется из сессии/JWT

    const playlist = await prisma.playlist.upsert({
      where: { spotifyId: spotifyPlaylistId },
      update: {
        name,
        description,
        imageUrl,
      },
      create: {
        userId,
        spotifyId: spotifyPlaylistId,
        name,
        description,
        imageUrl,
      },
    });

    res.status(200).json({ message: 'Playlist imported successfully', playlist });
  } catch (error) {
    console.error('Import Playlist Error:', error);
    res.status(500).json({ error: 'Failed to import playlist' });
  }
};

// Получение всех сохраненных плейлистов пользователя
exports.getUserPlaylists = async (req, res) => {
  try {
    const userId = req.user.id;
    const playlists = await prisma.playlist.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    res.status(200).json(playlists);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch playlists' });
  }
};
