const { t } = require('../infrastructure/i18n');
const axios = require('axios');
const prisma = require('../db/prisma');
const { OAuth2Client } = require('google-auth-library');
const crypto = require('crypto');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const fsp = require('fs/promises');
const { z } = require('zod');

const { getOrSet, incrementVersion, set: redisSet, get: redisGet, del: redisDel } = require('../infrastructure/redis');
const { encryptAccessToken, encryptRefreshToken } = require('../infrastructure/spotify/auth');
const { backfillArtwork } = require('../infrastructure/spotify/artwork');
const {
  issueAuthToken,
  revokeAuthToken,
  revokeAllUserTokens,
  listUserTokens,
  revokeUserTokenById,
} = require('../infrastructure/authTokens');
const { describeDevice, deviceIdFor } = require('../utils/device');
const {
  preferencesSchema,
  withDefaults,
  mergePreferences,
} = require('../utils/preferences');
const { getIo } = require('../socket');
const logger = require('../infrastructure/logger');
const asyncHandler = require('../utils/asyncHandler');
const { generateUniquePublicId } = require('../utils/publicId');
const { resolveOwnedUploadPath } = require('../utils/uploads');

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI = process.env.SPOTIFY_REDIRECT_URI;

const AVATARS_DIR = path.resolve(__dirname, '../../uploads/avatars');

const invalidateSessionsListForMembers = (members) =>
  Promise.all(
    (members || [])
      .filter((m) => m.status === 'accepted')
      .map((m) => incrementVersion(`db:sessions-list:${m.userId}`))
  );
const PENDING_AUTH_TTL_SECONDS = 5 * 60;

const APP_SCHEMES = ['myapp://', 'syncm://'];

function finishSpotifyLink(res, returnTo, params) {
  if (returnTo) {
    const joiner = returnTo.includes('?') ? '&' : '?';
    const isAppScheme = APP_SCHEMES.some((scheme) => returnTo.startsWith(scheme));
    const query = new URLSearchParams(params).toString();
    const prefix = isAppScheme ? '' : 'auth_done=1&';
    return res.redirect(`${returnTo}${joiner}${prefix}${query}`);
  }

  if (params.error) {
    res.set('Content-Type', 'text/html; charset=utf-8');
    return res.status(200).send(
      `<!doctype html><html lang="ru"><head><meta charset="utf-8">` +
        `<meta name="viewport" content="width=device-width,initial-scale=1">` +
        `<title>Подключение Spotify</title></head>` +
        `<body style="margin:0;display:flex;min-height:100vh;align-items:center;` +
        `justify-content:center;background:#121212;color:#ededed;` +
        `font:16px/1.5 system-ui,sans-serif">` +
        `<p style="max-width:26em;padding:24px;text-align:center">` +
        `${escapeHtml(params.error)}</p></body></html>`
    );
  }

  return null;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[ch]);
}
const allowedOrigins = (process.env.CLIENT_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

const LINK_INTENT_REGEX = /^[a-f0-9]{32}$/;
const LINK_INTENT_TTL_SECONDS = 10 * 60;
const OAUTH_STATE_TTL_SECONDS = 10 * 60;
const linkIntentKey = (id) => `oauth:link-intent:${id}`;
const oauthStateKey = (nonce) => `oauth:state:${nonce}`;

function isLoopbackOrigin(parsed) {
  return (
    parsed.protocol === 'http:' &&
    (parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1' || parsed.hostname === '[::1]')
  );
}

function sanitizeReturnTo(rawReturnTo) {
  if (!rawReturnTo || typeof rawReturnTo !== 'string') return null;
  const value = rawReturnTo.slice(0, 500);

  if (APP_SCHEMES.some((scheme) => value.startsWith(scheme))) return value;

  try {
    const parsed = new URL(value);
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    if (isLoopbackOrigin(parsed)) return value;
    if (!allowedOrigins.includes(parsed.origin)) return null;
    return value;
  } catch (err) {
    return null;
  }
}

const googleAuthSchema = z.object({
  idToken: z.string().min(1, 'Missing idToken'),
});

const oauthCallbackQuerySchema = z.object({
  code: z.string().min(1, 'Missing code'),
  state: z.string().optional(),
});

const httpUrlSchema = z.string().url('Некорректный URL аватарки').refine(
  (url) => /^https?:\/\//i.test(url),
  { message: 'Разрешены только http/https ссылки' }
);

const updateSettingsSchema = z.object({
  isOnlineHidden: z.boolean().optional(),
  isFriendsHidden: z.boolean().optional(),

  isSearchHidden: z.boolean().optional(),
  isActivityHidden: z.boolean().optional(),

  allowSessionInvites: z.enum(['friends', 'nobody']).optional(),

  preferences: preferencesSchema.optional(),
}).refine(data => Object.keys(data).length > 0, {
  message: 'Нет данных для обновления',
});

// Что отдаём как «настройки». Один набор для чтения и для ответа на запись —
// клиенту не приходится гадать, что изменилось.
const SETTINGS_SELECT = {
  isOnlineHidden: true,
  isFriendsHidden: true,
  isActivityHidden: true,
  isSearchHidden: true,
  allowSessionInvites: true,
  preferences: true,
};

const toSettingsResponse = (row) => ({
  isOnlineHidden: row.isOnlineHidden,
  isFriendsHidden: row.isFriendsHidden,
  isActivityHidden: row.isActivityHidden,
  isSearchHidden: row.isSearchHidden,
  allowSessionInvites: row.allowSessionInvites,
  preferences: withDefaults(row.preferences),
});

const updateProfileSchema = z.object({
  username: z.string().trim().min(2, 'Имя должно содержать минимум 2 символа')
    .max(50, 'Имя должно содержать не более 50 символов')
    .regex(/^[\p{L}\p{N} _\-\.]+$/u, 'Имя содержит недопустимые символы')
    .optional(),
  customAvatarUrl: httpUrlSchema.optional().nullable(),
}).refine(data => data.username !== undefined || data.customAvatarUrl !== undefined, {
  message: 'Нет данных для обновления',
});

const regenerateSession = (req) =>
  new Promise((resolve, reject) => req.session.regenerate((err) => (err ? reject(err) : resolve())));

const saveSession = (req) =>
  new Promise((resolve, reject) => req.session.save((err) => (err ? reject(err) : resolve())));

const destroySession = (req) =>
  new Promise((resolve, reject) => req.session.destroy((err) => (err ? reject(err) : resolve())));

async function loginAsUser(req, userId) {
  await regenerateSession(req);
  req.session.userId = userId;
  // Браузерная сессия — такой же сеанс, как токен приложения, и попадает в
  // тот же список устройств. Описание снимается один раз, при входе.
  req.session.device = describeDevice(req);
  req.session.createdAt = Date.now();
  req.session.lastSeenAt = Date.now();
  await saveSession(req);
}

const invalidateUserCaches = (userId) =>
  Promise.all([
    incrementVersion(`db:user-profile:${userId}`),
    incrementVersion(`db:user-settings:${userId}`),
  ]);

// Состояние подключения Spotify кэшируется отдельно и проверяется живым
// запросом (см. routes/spotify.js). После привязки аккаунта старый ответ
// «не подключён» провисел бы ещё пять минут, поэтому гасим его сразу.
const invalidateSpotifyCaches = (userId) =>
  Promise.all([
    incrementVersion(`spotify:status:${userId}`),
    incrementVersion(`spotify:token-info:${userId}`),
  ]);


const login = asyncHandler(async (req, res) => {
  const scopes = [
    'user-read-private', 'user-read-email', 'playlist-read-private',
    'playlist-read-collaborative', 'playlist-modify-public',
    'playlist-modify-private', 'user-library-read', 'streaming',
    'user-modify-playback-state', 'user-read-playback-state',
  ].join(' ');

  let linkUserId = null;
  let returnTo = '';

  const intentId = typeof req.query.state === 'string' ? req.query.state : null;
  if (intentId && LINK_INTENT_REGEX.test(intentId)) {
    const intent = await redisGet(linkIntentKey(intentId));
    if (intent) {
      linkUserId = intent.userId || null;
      returnTo = sanitizeReturnTo(intent.returnTo) || '';
      // Одноразовое: гасим сразу, повторно тем же значением воспользоваться нельзя.
      await redisDel(linkIntentKey(intentId));
    } else {
      logger.warn('Spotify link intent not found or expired');
    }
  }

  if (!linkUserId && req.session?.userId) {
    linkUserId = req.session.userId;
  }
  if (!returnTo) {
    returnTo = sanitizeReturnTo(req.query.returnTo) || '';
  }

  const nonce = crypto.randomBytes(16).toString('hex');
  req.session.spotifyOAuthState = nonce;
  req.session.spotifyOAuthReturnTo = returnTo;
  req.session.spotifyLinkUserId = linkUserId;
  await saveSession(req);

  await redisSet(
    oauthStateKey(nonce),
    { linkUserId, returnTo },
    OAUTH_STATE_TTL_SECONDS
  );

  const url = 'https://accounts.spotify.com/authorize' +
    '?response_type=code' +
    `&client_id=${encodeURIComponent(CLIENT_ID)}` +
    `&scope=${encodeURIComponent(scopes)}` +
    `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
    `&state=${encodeURIComponent(nonce)}` +
    '&show_dialog=true';

  res.redirect(url);
});

const callback = asyncHandler(async (req, res) => {
  const { code, state } = oauthCallbackQuerySchema.parse(req.query);

  const storedState = state ? await redisGet(oauthStateKey(state)) : null;
  const expectedState = req.session?.spotifyOAuthState;

  const sessionStateOk =
    expectedState &&
    state &&
    expectedState.length === state.length &&
    crypto.timingSafeEqual(Buffer.from(expectedState), Buffer.from(state));

  if (!storedState && !sessionStateOk) {
    logger.warn({ hasExpected: !!expectedState }, 'Spotify OAuth state mismatch');
    return res.status(400).json({ error: t(req, 'badOauthState') });
  }

  const returnTo = sanitizeReturnTo(storedState?.returnTo ?? req.session.spotifyOAuthReturnTo);
  const linkUserId =
    storedState?.linkUserId || req.session.spotifyLinkUserId || req.session.userId || null;

  // state одноразовый — гасим сразу после проверки.
  if (state) await redisDel(oauthStateKey(state));
  delete req.session.spotifyOAuthState;
  delete req.session.spotifyOAuthReturnTo;
  delete req.session.spotifyLinkUserId;

  const tokenResponse = await axios.post(
    'https://accounts.spotify.com/api/token',
    new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: REDIRECT_URI,
    }),
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString('base64')}`,
      },
      timeout: 10000,
    }
  );

  const { access_token, refresh_token } = tokenResponse.data;
  if (!access_token) {
    logger.error('Spotify token exchange returned no access_token');
    return res.status(502).json({ error: t(req, 'spotifyTokenFailed') });
  }

  let profile;
  try {
    const profileResponse = await axios.get('https://api.spotify.com/v1/me', {
      headers: { Authorization: `Bearer ${access_token}` },
      timeout: 10000,
    });
    profile = profileResponse.data;
  } catch (err) {
    const status = err.response?.status;
    logger.error(
      { status, data: err.response?.data },
      'Spotify /v1/me failed during callback'
    );

    const message =
      status === 403
        ? 'Этот аккаунт Spotify пока не допущен к приложению. Оно работает в режиме разработки, и подключиться могут только аккаунты из списка разработчика.'
        : 'Spotify не отдал данные аккаунта. Попробуйте подключиться ещё раз.';

    return finishSpotifyLink(res, returnTo, { error: message });
  }

  const existing = await prisma.spotifyUser.findUnique({
    where: { spotifyId: profile.id },
    select: { id: true },
  });
  const spotifyUserId = existing?.id || crypto.randomUUID();

  const encryptedTokens = {
    accessToken: await encryptAccessToken(spotifyUserId, access_token),
    ...(refresh_token && { refreshToken: await encryptRefreshToken(spotifyUserId, refresh_token) }),
  };

  const spotifyUser = await prisma.spotifyUser.upsert({
    where: { spotifyId: profile.id },
    update: {
      displayName: profile.display_name,
      email: profile.email,
      avatarUrl: profile.images?.[0]?.url || null,
      ...encryptedTokens,
      ...(linkUserId ? { userId: linkUserId } : {}),
    },
    create: {
      id: spotifyUserId,
      spotifyId: profile.id,
      displayName: profile.display_name,
      email: profile.email,
      avatarUrl: profile.images?.[0]?.url || null,
      ...encryptedTokens,
      ...(linkUserId ? { userId: linkUserId } : {}),
    },
  });

  let finalUserId = linkUserId;
  if (!finalUserId) {
    if (spotifyUser.userId) {
      finalUserId = spotifyUser.userId;
    } else {
      const newUser = await prisma.user.create({
        data: {
          publicId: await generateUniquePublicId(prisma),
          username: spotifyUser.displayName || spotifyUser.spotifyId,
          email: spotifyUser.email || `${spotifyUser.spotifyId}@spotify.user`,
          passwordHash: '',
          usernameChangedByUser: false,
          isEmailVerified: true,
        },
      });
      finalUserId = newUser.id;
      await prisma.spotifyUser.update({
        where: { id: spotifyUser.id },
        data: { userId: finalUserId },
      });
    }
  }

  await loginAsUser(req, finalUserId);
  await Promise.all([invalidateUserCaches(finalUserId), invalidateSpotifyCaches(finalUserId)]);

  const authToken = await issueAuthToken(finalUserId, { device: describeDevice(req) });
  const cookie = `connect.sid=${req.sessionID}`;

  const finished = finishSpotifyLink(res, returnTo, { token: authToken, cookie });
  if (finished !== null) return finished;

  res.json({
    message: 'Spotify подключен успешно',
    user: { id: finalUserId, displayName: spotifyUser.displayName, spotifyConnected: true },
    authToken,
    cookie,
  });
});

const createSpotifyLinkIntent = asyncHandler(async (req, res) => {
  const userId = req.userId;
  const returnTo = sanitizeReturnTo(req.body?.returnTo);

  if (req.body?.returnTo && !returnTo) {
    return res.status(400).json({ error: t(req, 'badReturnUrl') });
  }

  const intentId = crypto.randomBytes(16).toString('hex');
  await redisSet(linkIntentKey(intentId), { userId, returnTo }, LINK_INTENT_TTL_SECONDS);

  res.json({ state: intentId, expiresInSeconds: LINK_INTENT_TTL_SECONDS });
});

const getMe = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const userData = await getOrSet(`db:user-profile:${userId}`, 'me', 300, async () => {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        publicId: true,
        username: true,
        email: true,
        customAvatarUrl: true,
        isFriendsHidden: true,
        isSearchHidden: true,
        isActivityHidden: true,
        isOnlineHidden: true,
        spotifyUser: { select: { spotifyId: true, avatarUrl: true } },
      },
    });

    if (user) {
      return {
        id: user.id,
        publicId: user.publicId,
        displayName: user.username,
        email: user.email,
        avatarUrl: user.customAvatarUrl || user.spotifyUser?.avatarUrl || null,
        spotifyConnected: !!user.spotifyUser,
        spotifyId: user.spotifyUser?.spotifyId || null,
        isFriendsHidden: user.isFriendsHidden,

        isSearchHidden: user.isSearchHidden,
        isActivityHidden: user.isActivityHidden,
        isOnlineHidden: user.isOnlineHidden,
        customAvatarUrl: user.customAvatarUrl,
      };
    }

    const spotifyUser = await prisma.spotifyUser.findUnique({
      where: { id: userId },
      select: {
        id: true,
        userId: true,
        spotifyId: true,
        displayName: true,
        email: true,
        avatarUrl: true,
        user: {
          select: {
            publicId: true,
            username: true,
            email: true,
            isFriendsHidden: true,
            isSearchHidden: true,
            isActivityHidden: true,
            isOnlineHidden: true,
          },
        },
      },
    });
    if (spotifyUser) {
      return {
        id: spotifyUser.userId || spotifyUser.id,
        publicId: spotifyUser.user?.publicId || null,
        displayName: spotifyUser.user?.username || spotifyUser.displayName,
        email: spotifyUser.user?.email || spotifyUser.email,
        avatarUrl: spotifyUser.avatarUrl,
        spotifyConnected: true,
        spotifyId: spotifyUser.spotifyId,
        isFriendsHidden: spotifyUser.user?.isFriendsHidden ?? false,

        isSearchHidden: spotifyUser.user?.isSearchHidden ?? false,
        isActivityHidden: spotifyUser.user?.isActivityHidden ?? false,
        isOnlineHidden: spotifyUser.user?.isOnlineHidden ?? false,
      };
    }

    return null;
  });

  if (!userData) {
    return res.status(404).json({ error: t(req, 'userNotFound') });
  }

  const needsToken = req.authVia === 'session' && req.query.needToken === '1';
  if (needsToken) {
    try {
      const authToken = await issueAuthToken(userId, { device: describeDevice(req) });
      return res.json({ ...userData, authToken });
    } catch (err) {
      logger.error({ err, userId }, 'Failed to issue auth token in getMe');
    }
  }

  res.json(userData);
});

async function upsertGoogleUser(payload) {
  if (!payload.email_verified) {
    const err = new Error('Google account email is not verified');
    err.statusCode = 403;
    throw err;
  }

  const existing = await prisma.user.findUnique({ where: { email: payload.email } });

  const shouldSyncName =
    payload.name && (!existing || (!existing.usernameChangedByUser && existing.username !== payload.name));

  return prisma.user.upsert({
    where: { email: payload.email },
    update: shouldSyncName ? { username: payload.name } : {},
    create: {
      publicId: await generateUniquePublicId(prisma),
      username: payload.name || payload.email.split('@')[0],
      email: payload.email,
      passwordHash: '',
      isEmailVerified: true,
    },
  });
}

const googleAuth = asyncHandler(async (req, res) => {
  const { idToken } = googleAuthSchema.parse(req.body);

  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();

  let user;
  try {
    user = await upsertGoogleUser(payload);
  } catch (err) {
    if (err.statusCode === 403) return res.status(403).json({ error: t(req, 'googleEmailUnverified') });
    throw err;
  }

  await loginAsUser(req, user.id);
  await invalidateUserCaches(user.id);

  const authToken = await issueAuthToken(user.id, { device: describeDevice(req) });

  res.json({
    message: 'Logged in with Google',
    user: { id: user.id, displayName: user.username, email: user.email, spotifyConnected: false },
    authToken,
    cookie: `connect.sid=${req.sessionID}`,
  });
});

const logout = asyncHandler(async (req, res) => {
  const userId = req.session?.userId || req.userId;

  if (req.authToken) {
    await revokeAuthToken(req.authToken);
  }
  await destroySession(req);
  res.clearCookie('connect.sid');
  if (userId) await invalidateUserCaches(userId);
  res.json({ message: 'Вышли из системы' });
});

// Активные сеансы живут в двух местах: токены приложения — в Redis,
// браузерные сессии — в таблице express-session. Список показывает и те, и
// другие, иначе «выйти со всех устройств» выглядело бы враньём.
async function listWebSessions(userId) {
  const rows = await prisma.$queryRaw`
    SELECT sid, sess, expire
      FROM "session"
     WHERE sess->>'userId' = ${userId}
       AND expire > NOW()
  `;

  return rows.map((row) => {
    const sess = typeof row.sess === 'string' ? JSON.parse(row.sess) : row.sess;
    return {
      id: deviceIdFor(row.sid),
      kind: 'web',
      device: sess?.device || null,
      issuedAt: sess?.createdAt || null,
      lastSeenAt: sess?.lastSeenAt || sess?.createdAt || null,
    };
  });
}

// Какой из сеансов — этот самый. Считается из того, чем пришёл запрос, а не
// из данных клиента: подменить чужой «текущий» так нельзя.
function currentDeviceId(req) {
  if (req.authVia === 'token' && req.authToken) return deviceIdFor(req.authToken);
  if (req.sessionID) return deviceIdFor(req.sessionID);
  return null;
}

const deviceIdParamsSchema = z.object({
  deviceId: z.string().regex(/^[a-f0-9]{16}$/, 'Некорректный идентификатор устройства'),
});

const getDevices = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const [appSessions, webSessions] = await Promise.all([
    listUserTokens(userId),
    listWebSessions(userId),
  ]);

  const current = currentDeviceId(req);

  const devices = [...appSessions, ...webSessions]
    .map((device) => ({ ...device, current: device.id === current }))
    .sort((a, b) => (b.lastSeenAt || 0) - (a.lastSeenAt || 0));

  res.json({ devices });
});

const revokeDevice = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { deviceId } = deviceIdParamsSchema.parse(req.params);

  let revoked = await revokeUserTokenById(userId, deviceId);

  if (!revoked) {
    // Идентификатор — односторонний хеш, поэтому ищем перебором своих же
    // сессий. Условие по userId в запросе обязательно: без него чужой sid
    // с совпавшим хешем стал бы способом выкинуть другого человека.
    const rows = await prisma.$queryRaw`
      SELECT sid FROM "session" WHERE sess->>'userId' = ${userId}
    `;
    const match = rows.find((row) => deviceIdFor(row.sid) === deviceId);

    if (match) {
      await prisma.$executeRaw`DELETE FROM "session" WHERE sid = ${match.sid}`;
      revoked = true;
    }
  }

  if (!revoked) return res.status(404).json({ error: t(req, 'deviceNotFound') });

  // Сокет живёт своей жизнью: личность проверяется один раз, при подключении,
  // и отозванный сеанс продолжал бы получать события сессии. Разрываем все
  // сокеты пользователя — уцелевшие устройства переподключатся сами.
  try {
    getIo()?.in(`user:${userId}`).disconnectSockets(true);
  } catch (err) {
    logger.warn({ err, userId }, 'Не удалось разорвать сокеты после отзыва сеанса');
  }

  const wasCurrent = deviceId === currentDeviceId(req);
  if (wasCurrent && req.session) {
    await destroySession(req);
    res.clearCookie('connect.sid');
  }

  logger.info({ userId, wasCurrent }, 'Сеанс отозван');
  res.json({ message: 'Сеанс завершён', wasCurrent });
});

const logoutEverywhere = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  await revokeAllUserTokens(userId);
  await prisma.$executeRaw`DELETE FROM "session" WHERE sess->>'userId' = ${userId}`;

  try {
    getIo()?.in(`user:${userId}`).disconnectSockets(true);
  } catch (err) {
    logger.warn({ err, userId }, 'Не удалось разорвать сокеты при выходе со всех устройств');
  }

  // Текущая сессия уже удалена запросом выше, но объект в памяти о том не
  // знает — гасим и его, чтобы ответ не оставил живую куку.
  if (req.session) {
    try {
      await destroySession(req);
    } catch (err) {
      logger.warn({ err, userId }, 'Сессия уже удалена');
    }
    res.clearCookie('connect.sid');
  }

  await invalidateUserCaches(userId);

  logger.info({ userId }, 'Выход со всех устройств');
  res.json({ message: 'Вы вышли на всех устройствах' });
});

// Выгрузка собственных данных одним файлом.
//
// Собирается ровно то, что хранится о самом человеке. О других людях в
// выгрузку попадает минимум, без которого она бессмысленна: имя друга и
// название общей сессии — иначе это был бы список чужих профилей, скачанный
// по чужой воле.
const exportUserData = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      publicId: true,
      username: true,
      email: true,
      createdAt: true,
      customAvatarUrl: true,
      isOnlineHidden: true,
      isFriendsHidden: true,
      isActivityHidden: true,
      isSearchHidden: true,
      allowSessionInvites: true,
      preferences: true,
      spotifyUser: { select: { spotifyId: true, displayName: true } },
    },
  });

  if (!user) return res.status(404).json({ error: t(req, 'userNotFound') });

  const [friendships, playlists, likedTracks, playHistory, sessions] = await Promise.all([
    prisma.friendship.findMany({
      where: {
        status: 'accepted',
        OR: [{ senderId: userId }, { receiverId: userId }],
      },
      select: {
        createdAt: true,
        sender: { select: { id: true, username: true } },
        receiver: { select: { id: true, username: true } },
      },
    }),
    prisma.playlist.findMany({
      where: { userId },
      select: {
        name: true,
        description: true,
        isCustom: true,
        spotifyId: true,
        createdAt: true,
        playlistTracks: {
          orderBy: { position: 'asc' },
          select: {
            trackName: true,
            artistName: true,
            spotifyUri: true,
            addedAt: true,
          },
        },
      },
    }),
    prisma.likedTrack.findMany({
      where: { userId },
      select: { trackName: true, artistName: true, spotifyUri: true, likedAt: true },
      orderBy: { likedAt: 'desc' },
    }),
    prisma.playHistory.findMany({
      where: { userId },
      select: { trackName: true, artistName: true, spotifyUri: true, playedAt: true },
      orderBy: { playedAt: 'desc' },
      // История длинная и ценна как недавняя: тысяча записей — это месяцы
      // прослушивания и уже мегабайты файла.
      take: 1000,
    }),
    prisma.sessionMember.findMany({
      where: { userId },
      select: {
        status: true,
        joinedAt: true,
        session: {
          select: { name: true, createdAt: true, isActive: true, hostId: true },
        },
      },
      orderBy: { joinedAt: 'desc' },
      take: 500,
    }),
  ]);

  const data = {
    exportedAt: new Date().toISOString(),
    profile: {
      publicId: user.publicId,
      displayName: user.username,
      email: user.email,
      avatarUrl: user.customAvatarUrl,
      registeredAt: user.createdAt,
      spotify: user.spotifyUser
        ? { spotifyId: user.spotifyUser.spotifyId, displayName: user.spotifyUser.displayName }
        : null,
    },
    settings: {
      privacy: {
        isOnlineHidden: user.isOnlineHidden,
        isFriendsHidden: user.isFriendsHidden,
        isActivityHidden: user.isActivityHidden,
        isSearchHidden: user.isSearchHidden,
      },
      allowSessionInvites: user.allowSessionInvites,
      preferences: withDefaults(user.preferences),
    },
    friends: friendships.map((f) => {
      const other = f.sender.id === userId ? f.receiver : f.sender;
      return { displayName: other.username, since: f.createdAt };
    }),
    playlists: playlists.map((p) => ({
      name: p.name,
      description: p.description,
      source: p.isCustom ? 'syncm' : 'spotify',
      spotifyId: p.spotifyId,
      createdAt: p.createdAt,
      tracks: p.playlistTracks,
    })),
    likedTracks,
    playHistory,
    sessions: sessions.map((m) => ({
      name: m.session.name,
      role: m.session.hostId === userId ? 'host' : 'member',
      status: m.status,
      createdAt: m.session.createdAt,
      isActive: m.session.isActive,
      joinedAt: m.joinedAt,
    })),
  };

  const fileName = `syncm-data-${new Date().toISOString().slice(0, 10)}.json`;

  logger.info({ userId }, 'Выгрузка данных пользователя');

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
  res.send(JSON.stringify(data, null, 2));
});

const getSettings = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const settings = await getOrSet(`db:user-settings:${userId}`, 'settings:v2', 300, async () => {
    const row = await prisma.user.findUnique({
      where: { id: userId },
      select: SETTINGS_SELECT,
    });
    return row ? toSettingsResponse(row) : null;
  });

  if (!settings) return res.status(404).json({ error: t(req, 'userNotFound') });

  res.json(settings);
});

const updateSettings = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { preferences, ...dataToUpdate } = updateSettingsSchema.parse(req.body);

  // Настройки сливаются с сохранёнными, а не заменяют их целиком: клиент
  // присылает только изменённую группу, и остальные должны уцелеть. Чтение и
  // запись в одной транзакции — два устройства могут менять разные группы
  // одновременно, и без неё одно затёрло бы другое.
  const updated = await prisma.$transaction(async (tx) => {
    let data = dataToUpdate;

    if (preferences) {
      const current = await tx.user.findUnique({
        where: { id: userId },
        select: { preferences: true },
      });
      if (!current) return null;

      data = { ...data, preferences: mergePreferences(current.preferences, preferences) };
    }

    return tx.user.update({
      where: { id: userId },
      data,
      select: SETTINGS_SELECT,
    });
  });

  if (!updated) return res.status(404).json({ error: t(req, 'userNotFound') });

  await invalidateUserCaches(userId);
  res.json(toSettingsResponse(updated));
});

const updateProfile = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  const { username, customAvatarUrl } = updateProfileSchema.parse(req.body);

  const dataToUpdate = {};
  if (username !== undefined) {
    dataToUpdate.username = username;
    dataToUpdate.usernameChangedByUser = true;
  }
  if (customAvatarUrl !== undefined) {
    dataToUpdate.customAvatarUrl = customAvatarUrl || null;
  }

  const updated = await prisma.user.update({
    where: { id: userId },
    data: dataToUpdate,
    select: {
      id: true,
      username: true,
      customAvatarUrl: true,
      spotifyUser: { select: { avatarUrl: true } },
    },
  });

  await invalidateUserCaches(userId);

  res.json({
    id: updated.id,
    displayName: updated.username,
    avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
    customAvatarUrl: updated.customAvatarUrl,
  });
});

const googleWebLogin = asyncHandler(async (req, res) => {
  const returnTo = sanitizeReturnTo(req.query.returnTo) || '';

  const nonce = crypto.randomBytes(16).toString('hex');
  req.session.googleOAuthState = nonce;
  req.session.googleOAuthReturnTo = returnTo;
  await saveSession(req);

  const url = 'https://accounts.google.com/o/oauth2/v2/auth' +
    `?client_id=${encodeURIComponent(process.env.GOOGLE_CLIENT_ID)}` +
    `&redirect_uri=${encodeURIComponent(process.env.GOOGLE_REDIRECT_URI)}` +
    '&response_type=code' +
    '&scope=email%20profile' +
    `&state=${encodeURIComponent(nonce)}`;

  res.redirect(url);
});

const googleWebCallback = asyncHandler(async (req, res) => {
  const { code, state } = oauthCallbackQuerySchema.parse(req.query);

  const expectedState = req.session?.googleOAuthState;
  const stateOk =
    expectedState &&
    state &&
    expectedState.length === state.length &&
    crypto.timingSafeEqual(Buffer.from(expectedState), Buffer.from(state));

  if (!stateOk) {
    logger.warn({ hasExpected: !!expectedState }, 'Google OAuth state mismatch');
    return res.status(400).json({ error: t(req, 'badOauthState') });
  }

  const returnTo = sanitizeReturnTo(req.session.googleOAuthReturnTo);
  delete req.session.googleOAuthState;
  delete req.session.googleOAuthReturnTo;

  const tokenRes = await axios.post(
    'https://oauth2.googleapis.com/token',
    new URLSearchParams({
      code,
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      redirect_uri: process.env.GOOGLE_REDIRECT_URI,
      grant_type: 'authorization_code',
    }),
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, timeout: 10000 }
  );

  const { id_token } = tokenRes.data;
  if (!id_token) return res.status(502).json({ error: t(req, 'googleNoIdToken') });

  const ticket = await googleClient.verifyIdToken({
    idToken: id_token,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();

  let user;
  try {
    user = await upsertGoogleUser(payload);
  } catch (err) {
    if (err.statusCode === 403) return res.status(403).json({ error: t(req, 'googleEmailUnverified') });
    throw err;
  }

  await loginAsUser(req, user.id);
  await invalidateUserCaches(user.id);

  const authToken = await issueAuthToken(user.id, { device: describeDevice(req) });
  const cookie = `connect.sid=${req.sessionID}`;

  const tempToken = crypto.randomBytes(16).toString('hex');
  await redisSet(`auth:pending:${tempToken}`, { userId: user.id, authToken, cookie }, PENDING_AUTH_TTL_SECONDS);

  if (returnTo && !APP_SCHEMES.some((s) => returnTo.startsWith(s))) {
    const joiner = returnTo.includes('?') ? '&' : '?';
    return res.redirect(
      `${returnTo}${joiner}auth_done=1&token=${authToken}&cookie=${encodeURIComponent(cookie)}`
    );
  }

  res.send(`
    <html>
      <head>
        <title>SyncM — Вход выполнен</title>
        <style>
          body { font-family: sans-serif; text-align: center; padding: 60px; background: #111; color: #fff; }
          code { background: #222; padding: 8px 16px; border-radius: 8px; font-size: 20px; letter-spacing: 2px; }
          p { color: #aaa; }
        </style>
      </head>
      <body>
        <h2>Вход выполнен!</h2>
        <p>Введите этот код в приложении SyncM:</p>
        <code>${tempToken}</code>
        <p>Код действителен 5 минут.</p>
      </body>
    </html>
  `);
});

const checkPendingAuth = asyncHandler(async (req, res) => {
  const token = typeof req.query.token === 'string' ? req.query.token : '';
  if (!/^[a-f0-9]{32}$/.test(token)) {
    return res.json({ success: false });
  }

  const key = `auth:pending:${token}`;
  const data = await redisGet(key);
  if (data) {
    // Одноразовый: гасим сразу после выдачи.
    await redisDel(key);
    return res.json({ success: true, userId: data.userId, authToken: data.authToken, cookie: data.cookie });
  }
  res.json({ success: false });
});
const ALLOWED_MIME = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/gif': '.gif',
  'image/webp': '.webp',
};

const ALLOWED_EXT = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp']);

// Пакет http в Dart при MultipartFile.fromBytes без явного contentType
// проставляет application/octet-stream. Проверка только по MIME отклоняла
// такие загрузки, хотя файл корректный, — поэтому смотрим ещё и на
// расширение исходного имени.
function resolveImageExt(file) {
  const byMime = ALLOWED_MIME[file.mimetype];
  if (byMime) return byMime;
  const ext = path.extname(file.originalname || '').toLowerCase();
  if (ALLOWED_EXT.has(ext)) return ext === '.jpeg' ? '.jpg' : ext;
  return null;
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    fs.mkdir(AVATARS_DIR, { recursive: true }, (err) => cb(err, AVATARS_DIR));
  },
  filename: (req, file, cb) => {
    const ext = resolveImageExt(file) || '.png';
    const owner = req.userId || req.session?.userId || 'user';
    cb(null, `${owner}_${Date.now()}_${crypto.randomBytes(6).toString('hex')}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    if (resolveImageExt(file)) return cb(null, true);
    cb(new Error('Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP'), false);
  },
}).single('avatar');

const uploadAvatar = (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: t(req, 'unauthorized') });

  upload(req, res, async (err) => {
    if (err) {
      const message = err.message?.includes('Неподдерживаемый формат')
        ? err.message
        : `Ошибка загрузки файла: ${err.message}`;
      return res.status(400).json({ error: message });
    }
    if (!req.file) {
      return res.status(400).json({
        error: t(req, 'fileNotChosen'),
      });
    }

    const baseUrl = process.env.BASE_URL || `https://${req.get('host')}`;
    const avatarUrl = `${baseUrl}/uploads/avatars/${req.file.filename}`;

    try {
      const oldUser = await prisma.user.findUnique({
        where: { id: userId },
        select: { customAvatarUrl: true },
      });

      const updated = await prisma.user.update({
        where: { id: userId },
        data: { customAvatarUrl: avatarUrl },
        select: {
          id: true,
          username: true,
          customAvatarUrl: true,
          spotifyUser: { select: { avatarUrl: true } },
        },
      });

      await safeDeleteOldAvatar(oldUser?.customAvatarUrl, req.file.filename, userId);

      await invalidateUserCaches(userId);

      res.json({
        id: updated.id,
        displayName: updated.username,
        avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
        customAvatarUrl: updated.customAvatarUrl,
      });
    } catch (error) {
      logger.error({ err: error, userId }, 'Upload avatar error');
      // Не оставляем осиротевший файл, если запись в БД не удалась.
      await fsp.unlink(req.file.path).catch(() => {});
      res.status(500).json({ error: t(req, 'avatarSaveFailed') });
    }
  });
};

async function safeDeleteOldAvatar(oldAvatarUrl, currentFilename, ownerId) {
  if (!oldAvatarUrl) return;
  try {
    const resolved = resolveOwnedUploadPath(oldAvatarUrl, {
      dir: AVATARS_DIR,
      pathPrefix: '/uploads/avatars/',
      ownerId,
      skipFileName: currentFilename,
    });
    if (!resolved) return;

    await fsp.unlink(resolved);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      logger.warn({ err, oldAvatarUrl }, 'Could not delete old avatar file');
    }
  }
}


const deleteAccount = asyncHandler(async (req, res) => {
  const userId = req.userId;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, customAvatarUrl: true },
  });
  if (!user) return res.status(404).json({ error: t(req, 'userNotFound') });

  const hostedSessions = await prisma.session.findMany({
    where: { hostId: userId, isActive: true },
    include: { members: { select: { userId: true, status: true } } },
  });

  const io = getIo();
  for (const session of hostedSessions) {
    try {
      io?.to(session.id).emit('session_ended', {
        sessionId: session.id,
        endedBy: userId,
        reason: 'host_deleted',
        mutualLikes: [],
        timestamp: Date.now(),
      });
      await invalidateSessionsListForMembers(session.members);
    } catch (err) {
      logger.error({ err, sessionId: session.id }, 'Не удалось уведомить о закрытии сессии');
    }
  }

  if (user.customAvatarUrl) {
    try {
      // Тот же расчёт, что и при смене аватара: удаление своего аккаунта не
      // должно уносить с собой чужой файл, на который был подставлен URL.
      const resolved = resolveOwnedUploadPath(user.customAvatarUrl, {
        dir: AVATARS_DIR,
        pathPrefix: '/uploads/avatars/',
        ownerId: userId,
      });
      if (resolved) {
        await fs.promises.unlink(resolved).catch(() => {});
      }
    } catch (err) {
      logger.warn({ err, userId }, 'Не удалось удалить файл аватара');
    }
  }

  const friendships = await prisma.friendship.findMany({
    where: {
      status: 'accepted',
      OR: [{ senderId: userId }, { receiverId: userId }],
    },
    select: { senderId: true, receiverId: true },
  });

  const formerFriendIds = [
    ...new Set(
      friendships
        .map((f) => (f.senderId === userId ? f.receiverId : f.senderId))
        .filter((id) => id && id !== userId)
    ),
  ];

  if (formerFriendIds.length > 0) {
    await prisma.user.updateMany({
      where: { id: { in: formerFriendIds }, friendsCount: { gt: 0 } },
      data: { friendsCount: { decrement: 1 } },
    });
    await Promise.all(
      formerFriendIds.map((id) => incrementVersion(`db:friends-list:${id}`))
    );
  }

  await prisma.user.delete({ where: { id: userId } });

  await revokeAllUserTokens(userId);
  if (req.session) {
    await new Promise((resolve) => req.session.destroy(resolve));
    res.clearCookie('connect.sid');
  }

  logger.info({ userId, closedSessions: hostedSessions.length }, 'Аккаунт удалён');
  res.json({ message: 'Аккаунт удалён' });
});


const getPlayHistory = asyncHandler(async (req, res) => {
  const userId = req.userId;
  const rawLimit = Number.parseInt(req.query.limit, 10);
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 200) : 50;

  const rows = await prisma.playHistory.findMany({
    where: { userId },
    orderBy: { playedAt: 'desc' },
    take: limit * 4,
    select: {
      spotifyUri: true,
      trackName: true,
      artistName: true,
      imageUrl: true,
      playedAt: true,
    },
  });

  const seen = new Set();
  const unique = [];
  for (const row of rows) {
    if (seen.has(row.spotifyUri)) continue;
    seen.add(row.spotifyUri);
    unique.push(row);
    if (unique.length >= limit) break;
  }

  await backfillArtwork(userId, unique, 'playHistory');

  res.json(unique);
});

const clearPlayHistory = asyncHandler(async (req, res) => {
  const userId = req.userId;
  const { count } = await prisma.playHistory.deleteMany({ where: { userId } });

  logger.info({ userId, count }, 'Play history cleared');
  res.json({ message: 'История очищена', removed: count });
});

module.exports = {
  exportUserData,
  getDevices,
  revokeDevice,
  logoutEverywhere,
  login,
  callback,
  createSpotifyLinkIntent,
  getMe,
  logout,
  googleAuth,
  getSettings,
  updateSettings,
  updateProfile,
  googleWebLogin,
  googleWebCallback,
  checkPendingAuth,
  uploadAvatar,

  deleteAccount,

  getPlayHistory,

  clearPlayHistory,
};