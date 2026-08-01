const redis = require('../redis');
const logger = require('../logger');

const TTL_CONFIG = {
  track: 3600,
  playlist: 1800,
  playlist_items: 1800,
  search: 300,
  artist: 3600,
  album: 3600,
  user_playlists: 600,
  devices: 120,
  player_state: 10,
  default: 600,

  user_profile: 300,        // 5 минут
  user_settings: 300,       // 5 минут
  friends_list: 60,         // 1 минута
  friend_requests: 60,      // 1 минута
  search_users: 120,        // 2 минуты
  user_playlists_db: 300,   // 5 минут (плейлисты из БД)
  liked_tracks: 120,        // 2 минуты
  playlist_tracks_db: 300,  // 5 минут
  sessions_list: 30,        // 30 секунд (активные сессии)
  invites_list: 60,         // 1 минута
};

function getTTLForKey(key, explicitType = null) {
  if (explicitType && TTL_CONFIG[explicitType]) return TTL_CONFIG[explicitType];
  if (key.includes(':track:')) return TTL_CONFIG.track;
  if (key.includes(':playlist:')) {
    if (key.includes(':items')) return TTL_CONFIG.playlist_items;
    return TTL_CONFIG.playlist;
  }
  if (key.includes(':search:')) return TTL_CONFIG.search;
  if (key.includes(':artist:')) return TTL_CONFIG.artist;
  if (key.includes(':album:')) return TTL_CONFIG.album;
  if (key.includes(':user-playlists:')) return TTL_CONFIG.user_playlists;
  if (key.includes(':devices:')) return TTL_CONFIG.devices;
  if (key.includes(':player:')) return TTL_CONFIG.player_state;

  if (key.includes(':user-profile:')) return TTL_CONFIG.user_profile;
  if (key.includes(':user-settings:')) return TTL_CONFIG.user_settings;
  if (key.includes(':friends-list:')) return TTL_CONFIG.friends_list;
  if (key.includes(':friend-requests:')) return TTL_CONFIG.friend_requests;
  if (key.includes(':search-users:')) return TTL_CONFIG.search_users;
  if (key.includes(':user-playlists-db:')) return TTL_CONFIG.user_playlists_db;
  if (key.includes(':liked-tracks:')) return TTL_CONFIG.liked_tracks;
  if (key.includes(':playlist-tracks-db:')) return TTL_CONFIG.playlist_tracks_db;
  if (key.includes(':sessions-list:')) return TTL_CONFIG.sessions_list;
  if (key.includes(':invites-list:')) return TTL_CONFIG.invites_list;

  return TTL_CONFIG.default;
}

const STALE_EXTRA_MAX = 3600;

function getJitteredTTL(baseTtl, jitterFactor = 0.1) {
  const randomFactor = 1 + (Math.random() * jitterFactor * 2 - jitterFactor);
  return Math.max(1, Math.floor(baseTtl * randomFactor));
}

function getStaleExtraSeconds(baseTtl) {
  return Math.min(STALE_EXTRA_MAX, Math.max(baseTtl * 5, 30));
}

const pendingFetches = new Map();

async function fetchAndStore(cacheKey, baseTtl, jitter, lockTtlSeconds, fetchFn) {
  if (pendingFetches.has(cacheKey)) {
    return pendingFetches.get(cacheKey);
  }

  const promise = (async () => {
    const lockKey = `lock:${cacheKey}`;
    const token = await redis.acquireLock(lockKey, lockTtlSeconds);
    try {
      if (!token) {
        await new Promise(resolve => setTimeout(resolve, 150));
        try {
          const raw = await redis.redisClient.get(cacheKey);
          const parsed = raw ? JSON.parse(raw) : null;
          if (parsed?.exp > Date.now()) return parsed.data;
        } catch (err) {
        }
      }

      const fresh = await fetchFn();
      if (redis.isRedisAvailable()) {
        const finalTtl = getJitteredTTL(baseTtl, jitter);
        const logicalExpiry = Date.now() + finalTtl * 1000;
        const physicalTtl = finalTtl + getStaleExtraSeconds(finalTtl);
        await redis.redisClient
          .setex(cacheKey, physicalTtl, JSON.stringify({ data: fresh, exp: logicalExpiry }))
          .catch(err => logger.error({ err, cacheKey }, `Failed to set cache ${cacheKey}`));
      }
      return fresh;
    } finally {
      if (token) await redis.releaseLock(lockKey, token);
      pendingFetches.delete(cacheKey);
    }
  })();

  pendingFetches.set(cacheKey, promise);
  return promise;
}

async function getOrSet(cacheKey, ttlSeconds, fetchFn, options = {}) {
  const { staleWhileRevalidate = true, jitter = 0.1, lockTtlSeconds = 15 } = options;
  const baseTtl = ttlSeconds !== undefined ? ttlSeconds : getTTLForKey(cacheKey);

  let raw;
  try {
    raw = await redis.redisClient.get(cacheKey);
  } catch (err) {
    return fetchAndStore(cacheKey, baseTtl, jitter, lockTtlSeconds, fetchFn);
  }

  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed.exp === 'number' && parsed.data !== undefined) {
        const now = Date.now();
        if (parsed.exp > now) {
          logger.info({ cacheKey }, `Cache HIT (fresh)`);
          return parsed.data;
        } else if (staleWhileRevalidate && parsed.exp + getStaleExtraSeconds(baseTtl) * 1000 > now) {
          logger.info({ cacheKey }, `Cache STALE (will revalidate)`);
          fetchAndStore(cacheKey, baseTtl, jitter, lockTtlSeconds, fetchFn).catch(err =>
            logger.error({ err, cacheKey }, 'Background refresh failed')
          );
          return parsed.data; 
        }
      } else {
        logger.info({ cacheKey }, 'Cache HIT (old format, treating as fresh)');
        return parsed.data !== undefined ? parsed.data : parsed;
      }
    } catch (e) {
      logger.info({ cacheKey }, 'Cache HIT (plain value)');
      return raw;
    }
  }

  logger.info({ cacheKey }, 'Cache MISS');
  return fetchAndStore(cacheKey, baseTtl, jitter, lockTtlSeconds, fetchFn);
}

async function deleteKey(key) {
  if (!redis.isRedisAvailable()) return false;
  try {
    await redis.del(key);
    return true;
  } catch (err) {
    logger.error({ err, key }, 'Failed to delete cache key');
    return false;
  }
}

async function invalidateUserDB(userId, additionalKeys = []) {
  if (!redis.isRedisAvailable()) return false;

  const keysToDelete = [
    `db:user-profile:${userId}`,
    `db:user-settings:${userId}`,
    `db:user-playlists-db:${userId}`,
    `db:liked-tracks:${userId}`,
    `db:sessions-list:${userId}`,
    `db:invites-list:${userId}`,
    ...additionalKeys
  ];

  try {
    await Promise.all(keysToDelete.map(key => redis.del(key)));

    await redis.deleteByPattern(`db:friends-list:${userId}:*`);
    await redis.deleteByPattern(`db:friend-requests:${userId}:*`);
    await redis.deleteByPattern(`db:search-users:*:${userId}`);

    logger.info({ userId }, 'Invalidated DB cache for user');
    return true;
  } catch (err) {
    logger.error({ err, userId }, 'DB cache invalidation error');
    return false;
  }
}

module.exports = {
  getOrSet,
  getTTLForKey,
  TTL_CONFIG,
  deleteKey,
  invalidateUserDB
};