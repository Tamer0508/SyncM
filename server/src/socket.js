const prisma = require('./db/prisma');

const setupSocket = (io) => {
  io.on('connection', (socket) => {
    console.log('User connected:', socket.id);

    // Войти в комнату сессии
    socket.on('join_session', ({ sessionId, userId }) => {
      socket.join(sessionId);
      socket.data.userId = userId;
      socket.data.sessionId = sessionId;

      // Уведомить всех в комнате
      io.to(sessionId).emit('user_joined', { userId });
      console.log(`User ${userId} joined session ${sessionId}`);
    });

    // Играть трек
    socket.on('play', ({ sessionId, spotifyUri, position_ms }) => {
      // Отправить всем кроме отправителя
      socket.to(sessionId).emit('play', { spotifyUri, position_ms });
    });

    // Пауза
    socket.on('pause', ({ sessionId }) => {
      socket.to(sessionId).emit('pause');
    });

    // Следующий трек
    socket.on('next_track', ({ sessionId, spotifyUri }) => {
      socket.to(sessionId).emit('next_track', { spotifyUri });
    });

    // Перемотка
    socket.on('seek', ({ sessionId, position_ms }) => {
      socket.to(sessionId).emit('seek', { position_ms });
    });

    // Оценка трека сохранить в БД и уведомить комнату
    socket.on('rate_track', async ({ sessionId, trackId, rating, userId }) => {
      try {
        const existing = await prisma.trackRating.findFirst({
          where: { trackId, userId },
        });

        if (existing) {
          await prisma.trackRating.update({
            where: { id: existing.id },
            data: { rating },
          });
        } else {
          await prisma.trackRating.create({
            data: { trackId, userId, rating },
          });
        }

        // Уведомить всех в комнате об оценке
        io.to(sessionId).emit('track_rated', { trackId, userId, rating });
      } catch (error) {
        socket.emit('error', { message: 'Ошибка сохранения оценки' });
      }
    });

    // Выйти из сессии
    socket.on('leave_session', ({ sessionId, userId }) => {
      socket.leave(sessionId);
      io.to(sessionId).emit('user_left', { userId });
    });

    socket.on('disconnect', () => {
      const { userId, sessionId } = socket.data;
      if (sessionId && userId) {
        io.to(sessionId).emit('user_left', { userId });
      }
      console.log('User disconnected:', socket.id);
    });
  });
};

module.exports = setupSocket;