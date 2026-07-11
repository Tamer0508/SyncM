const { Queue, Worker } = require('bullmq');
const axios = require('axios');
const { redisClient } = require('./redis');
const { encrypt, decrypt } = require('../utils/crypto');
const prisma = require('../db/prisma');
const logger = require('./logger');
const { getIo } = require('../socket');

const connection = redisClient;

// Переменные, инициализируемые в initQueues
let notificationsQueue;
let notificationsDLQ;
let playlistSyncQueue;
let playlistSyncDLQ;
let notificationWorker;
let playlistSyncWorker;

/**
 * Отложенная инициализация очередей и воркеров.
 * Вызывать после того как Redis готов.
 */
function initQueues() {
  if (!connection) {
    logger.warn('Redis client is not available. BullMQ queues disabled.');
    return;
  }

  logger.info('Initializing BullMQ queues...');

  notificationsQueue = new Queue('notifications', { connection });
  notificationsDLQ = new Queue('notifications-dlq', { connection });
  playlistSyncQueue = new Queue('playlistSync', { connection });
  playlistSyncDLQ = new Queue('playlistSync-dlq', { connection });

  // Notification worker
  notificationWorker = new Worker(
    'notifications',
    async (job) => {
      const data = job.data || {};
      const io = getIo();
      if (!io) {
        logger.error({ jobId: job.id }, 'Socket.io instance is not available for notification');
        throw new Error('Socket.io instance is not available');
      }
      logger.debug({ jobId: job.id, type: data.type }, 'Processing notification job');

      switch (data.type) {
        case 'friend_request': {
          const { toUserId, fromUserId, fromUserName, requestId, timestamp } = data;
          if (!toUserId) throw new Error('Missing toUserId for friend_request');
          io.to(`user:${toUserId}`).emit('friend_request', {
            id: requestId,
            fromUserId,
            fromUserName,
            timestamp,
            status: 'pending',
          });
          logger.info({ toUserId, fromUserId, requestId }, 'Friend request notification sent');
          break;
        }
        case 'friend_request_accepted': {
          const { toUserId, fromUserId, fromUserName, friendshipId, timestamp } = data;
          if (!toUserId) throw new Error('Missing toUserId for friend_request_accepted');
          io.to(`user:${toUserId}`).emit('friend_request_accepted', {
            id: friendshipId,
            fromUserId,
            fromUserName,
            timestamp,
            status: 'accepted',
          });
          logger.info({ toUserId, fromUserId, friendshipId }, 'Friend request accepted notification sent');
          break;
        }
        case 'session_invite': {
          const { toUserId, sessionId, sessionName, hostId, timestamp } = data;
          if (!toUserId) throw new Error('Missing toUserId for session_invite');
          io.to(`user:${toUserId}`).emit('session_invite', {
            sessionId,
            sessionName,
            hostId,
            timestamp,
          });
          logger.info({ toUserId, sessionId, hostId }, 'Session invite notification sent');
          break;
        }
        case 'invite_response': {
          const { toUserId, userId, accept, sessionId, timestamp } = data;
          if (!toUserId) throw new Error('Missing toUserId for invite_response');
          io.to(`user:${toUserId}`).emit('invite_response', { userId, accept, sessionId, timestamp });
          logger.info({ toUserId, userId, accept, sessionId }, 'Invite response notification sent');
          break;
        }
        case 'tracks_added': {
          const { sessionId, tracks, allTracks, autoplayUri, autoplayIndex, addedById } = data;
          if (!sessionId) throw new Error('Missing sessionId for tracks_added');
          io.to(sessionId).emit('tracks-added', {
            tracks,
            allTracks,
            autoplayUri,
            autoplayIndex,
            addedById,
          });
          if (autoplayUri && autoplayIndex >= 0) {
            io.to(sessionId).emit('session_play', {
              spotifyUri: autoplayUri,
              trackIndex: autoplayIndex,
              addedById,
              tracks: allTracks,
            });
          }
          logger.info({ sessionId, trackCount: tracks?.length, autoplayIndex }, 'Tracks added notification sent');
          break;
        }
        case 'track_rated': {
          const { sessionId, trackId, userId, rating } = data;
          if (!sessionId) throw new Error('Missing sessionId for track_rated');
          io.to(sessionId).emit('track_rated', { trackId, userId, rating });
          logger.info({ sessionId, trackId, userId, rating }, 'Track rated notification sent');
          break;
        }
        case 'session_started': {
          const { toUserId, sessionId, sessionName, hostId, timestamp } = data;
          if (!toUserId) throw new Error('Missing toUserId for session_started');
          io.to(`user:${toUserId}`).emit('session_started', {
            sessionId,
            sessionName,
            hostId,
            timestamp,
          });
          logger.info({ toUserId, sessionId, hostId }, 'Session started notification sent');
          break;
        }
        default:
          logger.warn({ jobId: job.id, type: data.type }, 'Unknown notification job type');
          break;
      }
      return { processed: true, type: data.type };
    },
    {
      connection,
      concurrency: 5,
      removeOnComplete: { count: 100 },
      removeOnFail: { count: 100 },
    }
  );

  notificationWorker.on('failed', async (job, err) => {
    logger.error({ jobId: job.id, attemptsMade: job.attemptsMade, failedReason: err?.message }, 'Notification job failed');
    const maxAttempts = job.opts.attempts || 3;
    if (job.attemptsMade >= maxAttempts && notificationsDLQ) {
      try {
        await notificationsDLQ.add(
          `dlq-${job.id}-${Date.now()}`,
          {
            ...job.data,
            failedReason: err?.message,
            originalJobId: job.id,
            failedAt: new Date().toISOString(),
          },
          { removeOnComplete: true }
        );
        logger.warn({ jobId: job.id }, 'Moved notification job to DLQ');
      } catch (dlqError) {
        logger.error({ err: dlqError, originalJobId: job?.id }, 'Failed to move notification job to DLQ');
      }
    }
  });

  notificationWorker.on('completed', (job) => {
    logger.info({ jobId: job.id, type: job.data?.type }, 'Notification job completed');
  });

  // Playlist sync worker
  playlistSyncWorker = new Worker(
    'playlistSync',
    async (job) => {
      const { userId, playlistId, fullSync = false } = job.data;
      logger.info({ jobId: job.id, userId, playlistId, fullSync }, 'Processing playlist sync job');

      const spotifyUser = await prisma.spotifyUser.findFirst({
        where: { OR: [{ userId }, { id: userId }] }
      });
      if (!spotifyUser) throw new Error(`Spotify not connected for user ${userId}`);

      let accessToken;
      try {
        accessToken = decrypt(spotifyUser.accessToken);
      } catch (e) {
        throw new Error('Invalid Spotify token');
      }

      // Функция запроса с авто-обновлением токена и retry для 429
      const spotifyRequest = async (url, attempt = 1) => {
        const makeRequest = async (token) =>
          axios.get(url, {
            headers: { Authorization: `Bearer ${token}` },
            validateStatus: (status) => status < 500, // не кидать ошибку на 429, обработаем сами
          });

        let response;
        try {
          response = await makeRequest(accessToken);
        } catch (err) {
          if (err.response?.status === 401) {
            logger.info({ userId }, 'Spotify token expired, refreshing...');
            accessToken = await refreshAccessToken(spotifyUser);
            response = await makeRequest(accessToken);
          } else {
            throw err;
          }
        }

        if (response.status === 429 && attempt <= 5) {
          const retryAfter = parseInt(response.headers['retry-after'], 10) || 5;
          logger.warn({ url, attempt, retryAfter }, 'Spotify rate limited, retrying...');
          await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
          return spotifyRequest(url, attempt + 1);
        }

        if (response.status >= 400) {
          throw new Error(`Spotify API error ${response.status}: ${response.statusText}`);
        }

        return response.data;
      };

      // Получаем информацию о плейлисте
      const playlistData = await spotifyRequest(`https://api.spotify.com/v1/playlists/${playlistId}`);

      // Собираем все треки
      let trackItems = [];
      let nextUrl = `https://api.spotify.com/v1/playlists/${playlistId}/tracks?limit=50&market=from_token`;
      while (nextUrl) {
        const data = await spotifyRequest(nextUrl);
        trackItems.push(...data.items);
        nextUrl = data.next;
      }

      // Подготовка данных для пакетной вставки
      const tracks = trackItems
        .filter(item => item.track?.id)
        .map((item, index) => ({
          spotifyId: item.track.id,
          name: item.track.name,
          artist: item.track.artists?.map(a => a.name).join(', ') || '',
          album: item.track.album?.name || '',
          imageUrl: item.track.album?.images?.[0]?.url || null,
          durationMs: item.track.duration_ms,
          previewUrl: item.track.preview_url,
          spotifyUri: item.track.uri,
          position: index,
          addedAt: new Date(item.added_at || Date.now()),
        }));

      const trackSpotifyIds = tracks.map(t => t.spotifyId);

      // Транзакция с батчевыми операциями
      const result = await prisma.$transaction(async (tx) => {
        // Сохраняем плейлист
        const savedPlaylist = await tx.playlist.upsert({
          where: { spotifyId: playlistId },
          update: {
            name: playlistData.name,
            description: playlistData.description || '',
            imageUrl: playlistData.images?.[0]?.url || null,
            ownerName: playlistData.owner?.display_name || null,
            isPublic: playlistData.public || false,
            trackCount: tracks.length,
            lastSyncedAt: new Date(),
          },
          create: {
            spotifyId: playlistId,
            name: playlistData.name,
            description: playlistData.description || '',
            imageUrl: playlistData.images?.[0]?.url || null,
            ownerName: playlistData.owner?.display_name || null,
            isPublic: playlistData.public || false,
            trackCount: tracks.length,
            lastSyncedAt: new Date(),
          },
        });

        // Удаляем старые связи, если fullSync
        if (fullSync) {
          await tx.playlistTrack.deleteMany({ where: { playlistId: savedPlaylist.id } });
        }

        // Пакетная вставка треков (skipDuplicates)
        await tx.track.createMany({
          data: tracks.map(({ spotifyId, name, artist, album, imageUrl, durationMs, previewUrl, spotifyUri }) => ({
            spotifyId,
            name,
            artist,
            album,
            imageUrl,
            durationMs,
            previewUrl,
            spotifyUri,
          })),
          skipDuplicates: true,
        });

        // Получаем id всех треков, которые уже есть в БД
        const existingTracks = await tx.track.findMany({
          where: { spotifyId: { in: trackSpotifyIds } },
          select: { id: true, spotifyId: true },
        });
        const trackIdBySpotifyId = new Map(existingTracks.map(t => [t.spotifyId, t.id]));

        // Получаем существующие связи в плейлисте
        const existingLinks = await tx.playlistTrack.findMany({
          where: {
            playlistId: savedPlaylist.id,
            trackId: { in: existingTracks.map(t => t.id) },
          },
          select: { trackId: true },
        });
        const linkedTrackIds = new Set(existingLinks.map(l => l.trackId));

        // Подготовка новых связей
        const newLinks = [];
        for (const t of tracks) {
          const trackId = trackIdBySpotifyId.get(t.spotifyId);
          if (trackId && !linkedTrackIds.has(trackId)) {
            newLinks.push({
              playlistId: savedPlaylist.id,
              trackId,
              position: t.position,
              addedAt: t.addedAt,
            });
          }
        }

        if (newLinks.length > 0) {
          await tx.playlistTrack.createMany({
            data: newLinks,
            skipDuplicates: true,
          });
        }

        return {
          playlist: savedPlaylist,
          tracksAdded: newLinks.length,
          tracksAlreadyLinked: trackItems.length - newLinks.length,
          totalTracks: trackItems.length,
        };
      });

      // Инвалидация кэша Redis (можно использовать версионирование, но пока так)
      if (redisClient) {
        await Promise.all([
          redisClient.del(`spotify:user-playlists:${userId}`),
          redisClient.del(`spotify:playlist:${playlistId}:items`),
          redisClient.del(`spotify:playlist:${playlistId}:info`),
        ]);
      }

      logger.info({ jobId: job.id, playlistId, ...result }, 'Playlist sync completed');
      return { status: 'ok', syncedAt: new Date().toISOString(), ...result };
    },
    {
      connection,
      concurrency: 2,
      removeOnComplete: { count: 50 },
      removeOnFail: { count: 50 },
    }
  );

  playlistSyncWorker.on('failed', async (job, err) => {
    logger.error({ jobId: job.id, err: err?.message }, 'Playlist sync job failed');
    const maxAttempts = job.opts.attempts || 3;
    if (job.attemptsMade >= maxAttempts && playlistSyncDLQ) {
      try {
        await playlistSyncDLQ.add(
          `dlq-${job.id}-${Date.now()}`,
          {
            ...job.data,
            failedReason: err?.message,
            originalJobId: job.id,
            failedAt: new Date().toISOString(),
          },
          { removeOnComplete: true }
        );
        logger.warn({ jobId: job.id }, 'Moved playlist sync job to DLQ');
      } catch (dlqError) {
        logger.error({ err: dlqError, originalJobId: job?.id }, 'Failed to move playlist sync job to DLQ');
      }
    }
  });

  playlistSyncWorker.on('completed', (job) => {
    logger.info({ jobId: job.id, userId: job.data?.userId }, 'Playlist sync job completed');
  });

  logger.info('BullMQ queues initialized');
}

const refreshAccessToken = async (spotifyUser) => {
  const lockKey = `spotify:refresh_lock:${spotifyUser.id}`;
  try {
    const locked = await redisClient.set(lockKey, 'locked', 'EX', 5, 'NX');
    if (!locked) {
      logger.info({ userId: spotifyUser.userId }, 'Refresh token already in progress, waiting');
      await new Promise(resolve => setTimeout(resolve, 100));
      const freshSpotifyUser = await prisma.spotifyUser.findUnique({
        where: { id: spotifyUser.id }
      });
      if (freshSpotifyUser && freshSpotifyUser.accessToken) {
        const newToken = decrypt(freshSpotifyUser.accessToken);
        if (newToken) return newToken;
      }
      throw new Error('Could not obtain fresh token');
    }

    const decryptedRefreshToken = decrypt(spotifyUser.refreshToken);
    if (!decryptedRefreshToken) {
      throw new Error('Не удалось расшифровать refresh token');
    }

    const response = await axios.post(
      'https://accounts.spotify.com/api/token',
      new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: decryptedRefreshToken,
      }),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${Buffer.from(
            `${process.env.SPOTIFY_CLIENT_ID}:${process.env.SPOTIFY_CLIENT_SECRET}`
          ).toString('base64')}`,
        },
      }
    );

    const newAccessToken = response.data.access_token;
    await prisma.spotifyUser.update({
      where: { id: spotifyUser.id },
      data: {
        accessToken: encrypt(newAccessToken),
        ...(response.data.refresh_token && { refreshToken: encrypt(response.data.refresh_token) }),
      },
    });

    return newAccessToken;
  } finally {
    await redisClient.del(lockKey);
  }
};

const addNotificationJob = async (data) => {
  if (!notificationsQueue) throw new Error('Notifications queue is not available');
  return notificationsQueue.add('notification', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: false,
  });
};

const addPlaylistSyncJob = async (data) => {
  if (!playlistSyncQueue) throw new Error('Playlist sync queue is not available');
  return playlistSyncQueue.add('playlistSync', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: false,
  });
};

const closeQueues = async () => {
  logger.info('Closing BullMQ queues and workers...');
  const promises = [];
  if (notificationWorker) promises.push(notificationWorker.close());
  if (playlistSyncWorker) promises.push(playlistSyncWorker.close());
  if (notificationsQueue) promises.push(notificationsQueue.close());
  if (playlistSyncQueue) promises.push(playlistSyncQueue.close());
  if (notificationsDLQ) promises.push(notificationsDLQ.close());
  if (playlistSyncDLQ) promises.push(playlistSyncDLQ.close());
  await Promise.all(promises);
  logger.info('BullMQ queues closed');
};

module.exports = {
  initQueues,
  addNotificationJob,
  addPlaylistSyncJob,
  closeQueues,
};