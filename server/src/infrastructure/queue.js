const { Queue, Worker } = require('bullmq');
const Redis = require('ioredis');
const { redisClient, incrementVersion } = require('./redis');
const { withLock } = require('./lock');
const { getSpotifyUser, spotifyGet } = require('./spotify/auth');
const prisma = require('../db/prisma');
const logger = require('./logger');
const { getIo } = require('../socket');

const connection = redisClient;

let notificationsQueue;
let notificationsDLQ;
let playlistSyncQueue;
let playlistSyncDLQ;
let notificationWorker;
let playlistSyncWorker;
let workerConnection;

function initQueues() {
  if (!connection) {
    logger.warn('Redis client is not available. BullMQ queues disabled.');
    return;
  }

  logger.info('Initializing BullMQ queues...');

  workerConnection = new Redis(process.env.REDIS_URL, {
    maxRetriesPerRequest: null,
    enableReadyCheck: false,
    retryStrategy(times) {
      return Math.min(times * 50, 2000);
    },
  });
  workerConnection.on('error', (err) => {
    logger.error({ err }, 'BullMQ worker Redis connection error');
  });

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
      connection: workerConnection,
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

  playlistSyncWorker = new Worker(
    'playlistSync',
    async (job) => {
      const { userId, playlistId, fullSync = false } = job.data;
      logger.info({ jobId: job.id, userId, playlistId, fullSync }, 'Processing playlist sync job');

      return withLock(`playlist-sync:${playlistId}`, 60000, async () => {
        const spotifyUser = await getSpotifyUser(userId);
        if (!spotifyUser?.accessToken) throw new Error(`Spotify not connected for user ${userId}`);

        const playlistData = await spotifyGet(spotifyUser, `https://api.spotify.com/v1/playlists/${playlistId}`);

        let trackItems = [];
        let nextUrl = `https://api.spotify.com/v1/playlists/${playlistId}/items?limit=50`;
        while (nextUrl) {
          const data = await spotifyGet(spotifyUser, nextUrl);
          trackItems.push(...(data.items || []));
          nextUrl = data.next;
        }

        const trackRows = trackItems
          .map(entry => ({ track: entry.item || entry.track, addedAt: entry.added_at }))
          .filter(({ track }) => track?.id && track?.uri)
          .map(({ track, addedAt }) => ({
            spotifyUri: track.uri,
            trackName: track.name,
            artistName: track.artists?.map(a => a.name).join(', ') || '',
            durationMs: track.duration_ms ?? null,
            addedAt: new Date(addedAt || Date.now()),
          }));

        const result = await prisma.$transaction(async (tx) => {
          const savedPlaylist = await tx.playlist.upsert({
            where: { userId_spotifyId: { userId, spotifyId: playlistId } },
            update: {
              name: playlistData.name,
              description: playlistData.description || '',
              imageUrl: playlistData.images?.[0]?.url || null,
            },
            create: {
              userId,
              spotifyId: playlistId,
              name: playlistData.name,
              description: playlistData.description || '',
              imageUrl: playlistData.images?.[0]?.url || null,
              isCustom: false,
            },
          });

          if (fullSync) {
            await tx.playlistTrack.deleteMany({ where: { playlistId: savedPlaylist.id } });
          }

          let tracksAdded = 0;
          if (trackRows.length > 0) {
            const { count } = await tx.playlistTrack.createMany({
              data: trackRows.map(row => ({ ...row, playlistId: savedPlaylist.id })),
              skipDuplicates: true,
            });
            tracksAdded = count;
          }

          return {
            playlist: savedPlaylist,
            tracksAdded,
            totalTracks: trackRows.length,
          };
        }, {
          timeout: 20000,
        });

        await Promise.all([
          incrementVersion(`db:user-playlists-db:${userId}`),
          incrementVersion(`db:playlist-tracks-db:${result.playlist.id}`),
          incrementVersion(`spotify:user-playlists:${userId}`),
          incrementVersion(`spotify:playlist-tracks:${playlistId}`),
        ]);

        logger.info({ jobId: job.id, playlistId, ...result }, 'Playlist sync completed');
        return { status: 'ok', syncedAt: new Date().toISOString(), ...result };
      }, { failOpen: false });
    },
    {
      connection: workerConnection,
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

const addNotificationJob = async (data) => {
  if (!notificationsQueue) throw new Error('Notifications queue is not available');
  return notificationsQueue.add('notification', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: { count: 100 },
  });
};

const addPlaylistSyncJob = async (data) => {
  if (!playlistSyncQueue) throw new Error('Playlist sync queue is not available');
  return playlistSyncQueue.add('playlistSync', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: { count: 50 },
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
  if (workerConnection) await workerConnection.quit();
  logger.info('BullMQ queues closed');
};

module.exports = {
  initQueues,
  addNotificationJob,
  addPlaylistSyncJob,
  closeQueues,
};