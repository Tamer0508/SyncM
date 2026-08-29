

const MESSAGES = {
  unauthorized: {
    ru: 'Не авторизован',
    en: 'Not signed in',
  },
  forbidden: {
    ru: 'Нет доступа',
    en: 'No access',
  },
  notFound: {
    ru: 'Не найдено',
    en: 'Not found',
  },
  conflict: {
    ru: 'Такая запись уже существует',
    en: 'That record already exists',
  },
  recordNotFound: {
    ru: 'Запись не найдена',
    en: 'Record not found',
  },
  validationFailed: {
    ru: 'Ошибка валидации',
    en: 'Validation failed',
  },
  internalError: {
    ru: 'Внутренняя ошибка',
    en: 'Internal error',
  },
  userNotFound: {
    ru: 'Пользователь не найден',
    en: 'User not found',
  },

  cannotAddSelf: {
    ru: 'Нельзя добавить себя',
    en: "You can't add yourself",
  },
  cannotBlockSelf: {
    ru: 'Нельзя заблокировать себя',
    en: "You can't block yourself",
  },
  requestNotFound: {
    ru: 'Заявка не найдена или нет доступа',
    en: 'Request not found, or you have no access to it',
  },
  requestFailed: {
    ru: 'Не удалось отправить заявку',
    en: 'Could not send the request',
  },
  friendshipNotFound: {
    ru: 'Дружба не найдена',
    en: 'You are not friends'
  },
  friendshipAlreadyRemoved: {
    ru: 'Дружба уже удалена',
    en: 'The friendship is already removed',
  },
  useFriendsByUser: {
    ru: 'Для удаления друга используйте /friends/by-user/:friendId',
    en: 'Use /friends/by-user/:friendId to remove a friend',
  },

  notFriends: {
    ru: 'Вы не друзья с этим пользователем',
    en: 'You are not friends with this person',
  },
  cannotSessionWithSelf: {
    ru: 'Нельзя создать сессию с самим собой',
    en: "You can't start a session with yourself",
  },
  sessionNotFound: {
    ru: 'Сессия не найдена',
    en: 'Session not found',
  },
  sessionNotActive: {
    ru: 'Сессия не активна',
    en: 'The session is not active',
  },
  sessionAlreadyEnded: {
    ru: 'Сессия уже завершена',
    en: 'The session has already ended',
  },
  sessionNotMember: {
    ru: 'Вы не участник этой сессии',
    en: 'You are not a member of this session',
  },
  onlyHostCanEnd: {
    ru: 'Только создатель сессии может её завершить',
    en: 'Only the session host can end it',
  },
  inviteNotFound: {
    ru: 'Приглашение не найдено',
    en: 'Invitation not found',
  },
  invitesDisabled: {
    ru: '{name} отключил приглашения в сессии',
    en: '{name} has turned session invitations off',
  },

  untitledPlaylist: {
    ru: 'Без названия',
    en: 'Untitled',
  },
  untitledSession: {
    ru: 'Сессия',
    en: 'Session',
  },

  playlistNotFound: {
    ru: 'Плейлист не найден',
    en: 'Playlist not found',
  },
  playlistNoAccess: {
    ru: 'Нет доступа к этому плейлисту',
    en: 'No access to this playlist',
  },
  playlistImported: {
    ru: 'Нельзя удалить импортированный плейлист',
    en: "An imported playlist can't be deleted",
  },
  trackNotFound: {
    ru: 'Трек не найден',
    en: 'Track not found',
  },
  trackAlreadyInPlaylist: {
    ru: 'Трек уже есть в этом плейлисте',
    en: 'That track is already in this playlist',
  },

  fileNotChosen: {
    ru: 'Файл не выбран или имеет неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
    en: 'No file chosen, or the format is unsupported. Allowed: PNG, JPG, JPEG, GIF, WEBP',
  },
  avatarSaveFailed: {
    ru: 'Ошибка сохранения аватарки',
    en: 'Could not save the avatar',
  },
  coverSaveFailed: {
    ru: 'Ошибка сохранения обложки',
    en: 'Could not save the cover',
  },

  googleEmailUnverified: {
    ru: 'Email в Google-аккаунте не подтверждён',
    en: 'The email on the Google account is not verified',
  },
  googleNoIdToken: {
    ru: 'Google не вернул id_token',
    en: 'Google returned no id_token',
  },
  badReturnUrl: {
    ru: 'Недопустимый адрес возврата',
    en: 'Invalid return address',
  },
  badOauthState: {
    ru: 'Некорректный или устаревший запрос авторизации',
    en: 'The authorisation request is invalid or expired',
  },
  spotifyTokenFailed: {
    ru: 'Не удалось получить токен Spotify',
    en: 'Could not get a Spotify token',
  },
  spotifyNotConnected: {
    ru: 'Spotify не подключён',
    en: 'Spotify is not connected',
  },
  spotifyNoDevice: {
    ru: 'Нет активного устройства Spotify',
    en: 'No active Spotify device',
  },
  spotifyPremiumRequired: {
    ru: 'Действие недоступно (нужен Spotify Premium или другое устройство)',
    en: 'Unavailable — Spotify Premium or another device is required',
  },
  spotifyRateLimited: {
    ru: 'Spotify временно ограничил запросы, попробуйте позже',
    en: 'Spotify is rate-limiting requests, try again later',
  },
  spotifyApiError: {
    ru: 'Ошибка Spotify API',
    en: 'Spotify API error',
  },

  deviceNotFound: {
    ru: 'Сеанс не найден',
    en: 'Session not found',
  },
  deviceRevoked: {
    ru: 'Сеанс завершён',
    en: 'Session ended',
  },
  loggedOutEverywhere: {
    ru: 'Вы вышли на всех устройствах',
    en: 'You are signed out everywhere',
  },
};

const SUPPORTED = ['ru', 'en'];
const DEFAULT_LANGUAGE = 'ru';

function languageOf(req) {
  const header = req?.headers?.['accept-language'];
  if (!header || typeof header !== 'string') return DEFAULT_LANGUAGE;

  const candidates = header
    .split(',')
    .map((part) => {
      const [tag, ...params] = part.trim().split(';');
      const q = params
        .map((p) => p.trim())
        .find((p) => p.startsWith('q='));
      return {
        language: tag.trim().toLowerCase().split('-')[0],
        weight: q ? Number.parseFloat(q.slice(2)) || 0 : 1,
      };
    })
    .filter((c) => SUPPORTED.includes(c.language))
    .sort((a, b) => b.weight - a.weight);

  return candidates[0]?.language || DEFAULT_LANGUAGE;
}

function t(req, key, params = {}) {
  const entry = MESSAGES[key];
  if (!entry) {
    return key;
  }

  const language = languageOf(req);
  const template = entry[language] || entry[DEFAULT_LANGUAGE];

  return Object.entries(params).reduce(
    (text, [name, value]) => text.replaceAll(`{${name}}`, String(value)),
    template
  );
}

module.exports = { t, languageOf, MESSAGES, SUPPORTED, DEFAULT_LANGUAGE };
