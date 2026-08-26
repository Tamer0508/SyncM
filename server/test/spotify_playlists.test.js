'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isPlaylistOwnedByCurrentUser,
  isPlaylistEditableByCurrentUser,
  isPlaylistReadable,
  isPlaylistUsableForCurrentUser,
} = require('../src/infrastructure/spotify/playlists');

const ME = 'me-spotify-id';

const playlist = (over = {}) => ({
  type: 'playlist',
  id: 'pl1',
  name: 'Плейлист',
  public: true,
  collaborative: false,
  owner: { id: ME, display_name: 'Я' },
  ...over,
});

// ---------- OWNED ----------

test('владелец определяется по owner.id, а не по названию', () => {
  assert.equal(isPlaylistOwnedByCurrentUser(playlist(), ME), true);
  assert.equal(
    isPlaylistOwnedByCurrentUser(playlist({ owner: { id: 'friend' } }), ME),
    false
  );
});

test('без spotifyId текущего пользователя владельцем никто не считается', () => {
  assert.equal(isPlaylistOwnedByCurrentUser(playlist(), null), false);
  assert.equal(isPlaylistOwnedByCurrentUser(playlist(), ''), false);
});

// ---------- EDITABLE ----------

test('менять можно свой плейлист и совместный', () => {
  assert.equal(isPlaylistEditableByCurrentUser(playlist(), ME), true);
  assert.equal(
    isPlaylistEditableByCurrentUser(
      playlist({ owner: { id: 'friend' }, collaborative: true }),
      ME
    ),
    true
  );
});

test('чужой несовместный плейлист менять нельзя, даже публичный', () => {
  assert.equal(
    isPlaylistEditableByCurrentUser(
      playlist({ owner: { id: 'friend' }, public: true }),
      ME
    ),
    false
  );
});

// ---------- READABLE ----------

test('чужой плейлист читается: право на чтение не выводится из владения', () => {
  assert.equal(isPlaylistReadable(playlist({ owner: { id: 'friend' } })), true);
});

test('приватность к чтению отношения не имеет', () => {
  assert.equal(isPlaylistReadable(playlist({ public: false })), true);
  assert.equal(isPlaylistReadable(playlist({ public: null })), true);
});

test('удалённый плейлист приходит как null и отсеивается', () => {
  assert.equal(isPlaylistReadable(null), false);
  assert.equal(isPlaylistReadable(undefined), false);
});

test('запись без id или без владельца открыть нечем', () => {
  assert.equal(isPlaylistReadable(playlist({ id: null })), false);
  assert.equal(isPlaylistReadable(playlist({ id: '' })), false);
  assert.equal(isPlaylistReadable(playlist({ owner: null })), false);
  assert.equal(isPlaylistReadable(playlist({ owner: {} })), false);
});

test('не плейлист — не плейлист', () => {
  assert.equal(isPlaylistReadable(playlist({ type: 'episode' })), false);
  // Поля type может не быть вовсе: это не повод выбрасывать запись.
  assert.equal(isPlaylistReadable(playlist({ type: undefined })), true);
});

test('подборки самой Spotify недоступны приложению и в список не идут', () => {
  const discoverWeekly = playlist({
    id: '37i9dQZEVXcJZyENOWUFo7',
    name: 'Discover Weekly',
    owner: { id: 'spotify', display_name: 'Spotify' },
  });
  assert.equal(isPlaylistReadable(discoverWeekly), false);
});

// ---------- Пригодность в контексте ----------

test('для списка спрашивается чтение, и чужие плейлисты остаются', () => {
  const friends = playlist({ owner: { id: 'friend' } });
  assert.equal(
    isPlaylistUsableForCurrentUser(friends, { currentSpotifyId: ME }),
    true
  );
  assert.equal(
    isPlaylistUsableForCurrentUser(friends, {
      currentSpotifyId: ME,
      capability: 'read',
    }),
    true
  );
});

test('для правки чужой плейлист непригоден, свой — пригоден', () => {
  const friends = playlist({ owner: { id: 'friend' } });
  assert.equal(
    isPlaylistUsableForCurrentUser(friends, {
      currentSpotifyId: ME,
      capability: 'edit',
    }),
    false
  );
  assert.equal(
    isPlaylistUsableForCurrentUser(playlist(), {
      currentSpotifyId: ME,
      capability: 'edit',
    }),
    true
  );
});

test('нечитаемое непригодно и для правки, даже если владелец совпал', () => {
  assert.equal(
    isPlaylistUsableForCurrentUser(playlist({ id: null }), {
      currentSpotifyId: ME,
      capability: 'edit',
    }),
    false
  );
});

test('отбор списка не роняется на одной битой записи', () => {
  const all = [
    playlist({ id: 'ok1' }),
    null,
    playlist({ id: 'ok2', owner: { id: 'friend' } }),
    playlist({ id: null }),
    playlist({ id: 'editorial', owner: { id: 'spotify' } }),
    playlist({ id: 'ok3', public: false }),
  ];

  const visible = all
    .filter((p) => isPlaylistUsableForCurrentUser(p, { currentSpotifyId: ME }))
    .map((p) => p.id);

  assert.deepEqual(visible, ['ok1', 'ok2', 'ok3']);
});
