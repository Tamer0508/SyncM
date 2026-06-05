const { Queue, Worker } = require('bullmq');
const axios = require('axios');
const { redisClient } = require('./redis');
const { encrypt, decrypt } = require('../utils/crypto');
const prisma = require('../db/prisma');
const logger = require('./logger');
const { getIo } = require('../socket');

const connection = redisClient;
const hasRedis = Boolean(connection);

if (!hasRedis) {
  logger.warn('Redis client is not available. BullMQ queues are disabled.');
}

// Очереди
const notificationsQueue = hasRedis ? new Queue('notifications', { connection }) : null;
const notificationsDLQ = hasRedis ? new Queue('notifications-dlq', { connection }) : null;
const playlistSyncQueue = hasRedis ? new Queue('playlistSync', { connection }) : null;

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

const notificationWorker = hasRedis ? new Worker(
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
) : null;

if (notificationWorker) {
  notificationWorker.on('failed', async (job, err) => {
    try {
      logger.error({ jobId: job.id, attemptsMade: job.attemptsMade, failedReason: err?.message }, 'Notification job failed');
      const maxAttempts = job.opts.attempts || 3;
      if (job.attemptsMade >= maxAttempts && notificationsDLQ) {
        await notificationsDLQ.add(
          `dlq-${job.id}-${Date.now()}`,
          { ...job.data, failedReason: err?.message, originalJobId: job.id, failedAt: new Date().toISOString() },
          { removeOnComplete: true }
        );
        logger.warn({ jobId: job.id }, 'Moved notification job to DLQ');
      }
    } catch (dlqError) {
      logger.error({ err: dlqError, originalJobId: job?.id }, 'Failed to move notification job to DLQ');
    }
  });
  notificationWorker.on('completed', (job) => {
    logger.info({ jobId: job.id, type: job.data?.type }, 'Notification job completed');
  });
}

const playlistSyncWorker = hasRedis ? new Worker(
  'playlistSync',
  async (job) => {
    const { userId, playlistId, fullSync = false } = job.data;
    logger.info({ jobId: job.id, userId, playlistId, fullSync }, 'Processing playlist sync job');

    try {
      // 1. Получаем Spotify-аккаунт пользователя
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

      // 2. Функция запроса с авто-обновлением токена
      const spotifyRequest = async (url) => {
        const makeRequest = async (token) => axios.get(url, { headers: { Authorization: `Bearer ${token}` } });
        try {
          return await makeRequest(accessToken);
        } catch (err) {
          if (err.response?.status === 401) {
            logger.info({ userId }, 'Spotify token expired, refreshing...');
            accessToken = await refreshAccessToken(spotifyUser);
            return makeRequest(accessToken);
          }
          throw err;
        }
      };

      // 3. Получаем данные плейлиста
      const playlistInfo = await spotifyRequest(`https://api.spotify.com/v1/playlists/${playlistId}`);
      const playlistData = playlistInfo.data;

      let tracks = [];
      let nextUrl = `https://api.spotify.com/v1/playlists/${playlistId}/tracks?limit=50&market=from_token`;
      while (nextUrl) {
        const response = await spotifyRequest(nextUrl);
        tracks.push(...response.data.items);
        nextUrl = response.data.next;
        if (nextUrl) await new Promise(resolve => setTimeout(resolve, 100));
      }

      // 4. Сохраняем в БД транзакцией
      const result = await prisma.$transaction(async (tx) => {
        const savedPlaylist = await tx.playlist.upsert({
          where: { spotifyId: playlistId },
          update: {
            name: playlistData.name,
            description: playlistData.description || '',
            imageUrl: playlistData.images?.[0]?.url || null,
            ownerName: playlistData.owner?.display_name || null,
            isPublic: playlistData.public || false,
            trackCount: tracks.length,
            lastSyncedAt: new Date()
          },
          create: {
            spotifyId: playlistId,
            name: playlistData.name,
            description: playlistData.description || '',
            imageUrl: playlistData.images?.[0]?.url || null,
            ownerName: playlistData.owner?.display_name || null,
            isPublic: playlistData.public || false,
            trackCount: tracks.length,
            lastSyncedAt: new Date()
          }
        });

        if (fullSync) {
          await tx.playlistTrack.deleteMany({ where: { playlistId: savedPlaylist.id } });
        }

        let tracksAdded = 0, tracksUpdated = 0;
        for (let i = 0; i < tracks.length; i++) {
          const track = tracks[i].track;
          if (!track?.id) continue;

          const savedTrack = await tx.track.upsert({
            where: { spotifyId: track.id },
            update: {
              name: track.name,
              artist: track.artists?.map(a => a.name).join(', ') || '',
              album: track.album?.name || '',
              imageUrl: track.album?.images?.[0]?.url || null,
              durationMs: track.duration_ms,
              previewUrl: track.preview_url,
              spotifyUri: track.uri
            },
            create: {
              spotifyId: track.id,
              name: track.name,
              artist: track.artists?.map(a => a.name).join(', ') || '',
              album: track.album?.name || '',
              imageUrl: track.album?.images?.[0]?.url || null,
              durationMs: track.duration_ms,
              previewUrl: track.preview_url,
              spotifyUri: track.uri
            }
          });

          const existing = await tx.playlistTrack.findUnique({
            where: { playlistId_trackId: { playlistId: savedPlaylist.id, trackId: savedTrack.id } }
          });
          if (!existing) {
            await tx.playlistTrack.create({
              data: {
                playlistId: savedPlaylist.id,
                trackId: savedTrack.id,
                position: i,
                addedAt: new Date(tracks[i].added_at || Date.now())
              }
            });
            tracksAdded++;
          } else {
            tracksUpdated++;
          }
        }
        return { playlist: savedPlaylist, tracksAdded, tracksUpdated, totalTracks: tracks.length };
      });

      // 5. Чистим кэш Redis
      await Promise.all([
        redisClient.del(`spotify:user-playlists:${userId}`),
        redisClient.del(`spotify:playlist:${playlistId}:items`),
        redisClient.del(`spotify:playlist:${playlistId}:info`)
      ]);

      logger.info({ jobId: job.id, playlistId, ...result }, 'Playlist sync completed');
      return { status: 'ok', syncedAt: new Date().toISOString(), ...result };
    } catch (error) {
      logger.error({ err: error, jobId: job.id, userId, playlistId }, 'Playlist sync failed');
      if (error.message.includes('token') || error.message.includes('Spotify not connected')) throw error;
      return { status: 'error', error: error.message };
    }
  },
  { connection, concurrency: 2, removeOnComplete: { count: 50 }, removeOnFail: { count: 50 } }
) : null;

if (playlistSyncWorker) {
  playlistSyncWorker.on('failed', (job, err) => logger.error({ jobId: job.id, err: err?.message }, 'Playlist sync job failed'));
  playlistSyncWorker.on('completed', (job) => logger.info({ jobId: job.id, userId: job.data?.userId }, 'Playlist sync job completed'));
}

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
  await Promise.all(promises);
  logger.info('BullMQ queues closed');
};

module.exports = {
  addNotificationJob,
  addPlaylistSyncJob,
  closeQueues,
};