'use strict';

const SPOTIFY_EDITORIAL_OWNER_ID = 'spotify';

const isNonEmptyString = (value) => typeof value === 'string' && value.length > 0;

function isPlaylistOwnedByCurrentUser(playlist, currentSpotifyId) {
  if (!playlist || !isNonEmptyString(currentSpotifyId)) return false;
  return playlist.owner?.id === currentSpotifyId;
}

function isPlaylistEditableByCurrentUser(playlist, currentSpotifyId) {
  if (!playlist) return false;
  return (
    isPlaylistOwnedByCurrentUser(playlist, currentSpotifyId) ||
    playlist.collaborative === true
  );
}

function isPlaylistReadable(playlist) {
  if (!playlist || typeof playlist !== 'object') return false;
  if (playlist.type !== undefined && playlist.type !== 'playlist') return false;
  if (!isNonEmptyString(playlist.id)) return false;
  if (!isNonEmptyString(playlist.owner?.id)) return false;
  if (playlist.owner.id === SPOTIFY_EDITORIAL_OWNER_ID) return false;
  return true;
}

function isPlaylistUsableForCurrentUser(playlist, options = {}) {
  const { currentSpotifyId = null, capability = 'read' } = options;

  if (!isPlaylistReadable(playlist)) return false;
  if (capability === 'edit') {
    return isPlaylistEditableByCurrentUser(playlist, currentSpotifyId);
  }
  return true;
}

module.exports = {
  SPOTIFY_EDITORIAL_OWNER_ID,
  isPlaylistOwnedByCurrentUser,
  isPlaylistEditableByCurrentUser,
  isPlaylistReadable,
  isPlaylistUsableForCurrentUser,
};
