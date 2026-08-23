const prisma = require('../../db/prisma');
const logger = require('../logger');
const { get: redisGet, set: redisSet } = require('../redis');
const { getSpotifyUser, spotifyGet } = require('./auth');


const BATCH_SIZE = 50;

const MAX_PER_REQUEST = 100;

const trackIdOf = (uri) => {
  if (typeof uri !== 'string') return null;
  const id = uri.includes(':') ? uri.split(':').pop() : uri;
  return /^[A-Za-z0-9]{22}$/.test(id) ? id : null;
};

async function fetchArtwork(userId, uris) {
  const byId = new Map();
  for (const uri of uris) {
    const id = trackIdOf(uri);
    if (id) byId.set(id, uri);
  }
  if (byId.size === 0) return new Map();

  const spotifyUser = await getSpotifyUser(userId);
  if (!spotifyUser?.accessToken) return new Map();

  const ids = [...byId.keys()];
  const result = new Map();

  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    const chunk = ids.slice(i, i + BATCH_SIZE);
    const data = await spotifyGet(
      spotifyUser,
      `https://api.spotify.com/v1/tracks?ids=${chunk.join(',')}`
    );

    for (const track of data?.tracks ?? []) {
      const image = track?.album?.images?.[0]?.url;
      const uri = track?.id ? byId.get(track.id) : null;
      if (image && uri) result.set(uri, image);
    }
  }

  return result;
}

const COOLDOWN_SECONDS = 60 * 60;
const cooldownKey = (userId) => `spotify:artwork-backfill-cooldown:${userId}`;

async function backfillArtwork(userId, rows, model) {
  const missing = rows.filter((row) => !row.imageUrl).slice(0, MAX_PER_REQUEST);
  if (missing.length === 0) return rows;

  const paused = await redisGet(cooldownKey(userId)).catch(() => null);
  if (paused) return rows;

  try {
    const artwork = await fetchArtwork(userId, missing.map((row) => row.spotifyUri));
    if (artwork.size === 0) return rows;

    await Promise.all(
      [...artwork].map(([spotifyUri, imageUrl]) =>
        prisma[model].updateMany({
          where: { userId, spotifyUri, imageUrl: null },
          data: { imageUrl },
        })
      )
    );

    for (const row of rows) {
      if (!row.imageUrl) {
        const found = artwork.get(row.spotifyUri);
        if (found) row.imageUrl = found;
      }
    }
  } catch (err) {
    logger.warn({ err, userId, model }, 'Could not backfill track artwork, pausing');
    await redisSet(cooldownKey(userId), true, COOLDOWN_SECONDS).catch(() => {});
  }

  return rows;
}

module.exports = { backfillArtwork };
