const { Queue, Worker, QueueScheduler } = require('bullmq');
const { redisClient } = require('./redis');
const { getIo } = require('../socket');
const logger = require('./logger');

const connection = redisClient;
const hasRedis = Boolean(connection);

if (!hasRedis) {
  logger.warn('Redis client is not available. BullMQ queues are disabled.');
}

const notificationsQueue = hasRedis ? new Queue('notifications', { connection }) : null;
const notificationsScheduler = hasRedis ? new QueueScheduler('notifications', { connection }) : null;
const notificationsDLQ = hasRedis ? new Queue('notifications-dlq', { connection }) : null;

const playlistSyncQueue = hasRedis ? new Queue('playlistSync', { connection }) : null;
const playlistSyncScheduler = hasRedis ? new QueueScheduler('playlistSync', { connection }) : null;

const notificationWorker = hasRedis ? new Worker(
  'notifications',
  async (job) => {
    const data = job.data || {};
    const io = getIo();
    if (!io) {
      throw new Error('Socket.io instance is not available');
    }

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
        break;
      }
      case 'invite_response': {
        const { toUserId, userId, accept, sessionId, timestamp } = data;
        if (!toUserId) throw new Error('Missing toUserId for invite_response');
        io.to(`user:${toUserId}`).emit('invite_response', { userId, accept, sessionId, timestamp });
        break;
      }
      case 'tracks_added': {
        const { sessionId, tracks } = data;
        if (!sessionId) throw new Error('Missing sessionId for tracks_added');
        io.to(sessionId).emit('tracks-added', tracks);
        break;
      }
      case 'track_rated': {
        const { sessionId, trackId, userId, rating } = data;
        if (!sessionId) throw new Error('Missing sessionId for track_rated');
        io.to(sessionId).emit('track_rated', { trackId, userId, rating });
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
        break;
      }
      default:
        logger.warn({ jobName: job.name, type: data.type }, 'Unknown notification job type');
        break;
    }
  },
  { connection }
) : null;

if (notificationWorker) {
  notificationWorker.on('failed', async (job, err) => {
    try {
      logger.error({ jobId: job.id, attemptsMade: job.attemptsMade, failedReason: err?.message }, 'Notification job failed');
      const maxAttempts = job.opts.attempts || 1;
      if (job.attemptsMade >= maxAttempts && notificationsDLQ) {
        await notificationsDLQ.add(
          `dlq-${job.id}-${Date.now()}`,
          { ...job.data, failedReason: err?.message },
          { removeOnComplete: true }
        );
        logger.warn({ jobId: job.id }, 'Moved notification job to DLQ');
      }
    } catch (dlqError) {
      logger.error({ err: dlqError }, 'Failed to move notification job to DLQ');
    }
  });
}

const playlistSyncWorker = hasRedis ? new Worker(
  'playlistSync',
  async (job) => {
    logger.info({ jobId: job.id, data: job.data }, 'Processing playlist sync job (stub)');
    // TODO: implement Spotify sync logic here.
    return { status: 'ok' };
  },
  { connection }
) : null;

const addNotificationJob = async (data) => {
  if (!notificationsQueue) {
    throw new Error('Notifications queue is not available because Redis is not configured');
  }
  return notificationsQueue.add('notification', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: false,
  });
};

const addPlaylistSyncJob = async (data) => {
  if (!playlistSyncQueue) {
    throw new Error('Playlist sync queue is not available because Redis is not configured');
  }
  return playlistSyncQueue.add('playlistSync', data, {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: false,
  });
};

module.exports = {
  addNotificationJob,
  addPlaylistSyncJob,
};
