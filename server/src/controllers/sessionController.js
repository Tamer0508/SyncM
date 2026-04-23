const prisma = require('../db/prisma');

// Создать сессию
const createSession = async (req, res) => {
  const { name, friendId } = req.body;
  const userId = req.session.userId;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const session = await prisma.session.create({
      data: {
        name,
        hostId: userId,
        members: {
          create: [
            { userId }, // хост
            { userId: friendId }, // друг
          ],
        },
      },
      include: {
        members: {
          include: {
            user: {
              select: { id: true, displayName: true, avatarUrl: true },
            },
          },
        },
      },
    });

    res.json(session);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка создания сессии' });
  }
};

// Получить активные сессии пользователя
const getMySessions = async (req, res) => {
  const userId = req.session.userId;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const sessions = await prisma.session.findMany({
      where: {
        isActive: true,
        members: {
          some: { userId },
        },
      },
      include: {
        members: {
          include: {
            user: {
              select: { id: true, displayName: true, avatarUrl: true },
            },
          },
        },
        tracks: true,
      },
    });

    res.json(sessions);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения сессий' });
  }
};

// Добавить треки в сессию
const addTracks = async (req, res) => {
  const { sessionId } = req.params;
  const { tracks } = req.body; // [{ spotifyUri, trackName, artistName }]
  const userId = req.session.userId;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const created = await prisma.sessionTrack.createMany({
      data: tracks.map((t) => ({
        sessionId,
        spotifyUri: t.spotifyUri,
        trackName: t.trackName,
        artistName: t.artistName,
      })),
    });

    res.json({ message: `Добавлено ${created.count} треков` });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка добавления треков' });
  }
};

// Оценить трек
const rateTrack = async (req, res) => {
  const { trackId } = req.params;
  const { rating } = req.body; // 1 или -1
  const userId = req.session.userId;

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const existing = await prisma.trackRating.findFirst({
      where: { trackId, userId },
    });

    let result;
    if (existing) {
      result = await prisma.trackRating.update({
        where: { id: existing.id },
        data: { rating },
      });
    } else {
      result = await prisma.trackRating.create({
        data: { trackId, userId, rating },
      });
    }

    res.json(result);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка оценки' });
  }
};

// Завершить сессию и получить треки которые понравились обоим
const endSession = async (req, res) => {
  const { sessionId } = req.params;

  try {
    // Деактивируем сессию
    await prisma.session.update({
      where: { id: sessionId },
      data: { isActive: false },
    });

    // Находим треки с двумя лайками
    const tracks = await prisma.sessionTrack.findMany({
      where: { sessionId },
      include: { ratings: true },
    });

    const mutualLikes = tracks.filter(
      (track) =>
        track.ratings.length === 2 &&
        track.ratings.every((r) => r.rating === 1)
    );

    res.json({
      message: 'Сессия завершена',
      mutualLikes,
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка завершения сессии' });
  }
};

module.exports = {
  createSession,
  getMySessions,
  addTracks,
  rateTrack,
  endSession,
};