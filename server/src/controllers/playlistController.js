const prisma = require('../db/prisma');

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

exports.importPlaylist = async (req, res) => {
  try {
    const { spotifyPlaylistId, name, description, imageUrl } = req.body;
    const userId = getUserId(req);

    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const playlist = await prisma.playlist.upsert({
      where: { spotifyId: spotifyPlaylistId },
      update: { name, description, imageUrl },
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
    res.status(500).json({ error: 'Failed to fetch playlists' });
  }
};
