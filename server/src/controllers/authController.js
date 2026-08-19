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
const { issueAuthToken, revokeAuthToken, revokeAllUserTokens } = require('../infrastructure/authTokens');
const { getIo } = require('../socket');
const logger = require('../infrastructure/logger');
const asyncHandler = require('../utils/asyncHandler');
const { generateUniquePublicId } = require('../utils/publicId');

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
}).refine(data => Object.keys(data).length > 0, {
  message: 'Нет данных для обновления',
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
  await saveSession(req);
}

const invalidateUserCaches = (userId) =>
  Promise.all([
    incrementVersion(`db:user-profile:${userId}`),
    incrementVersion(`db:user-settings:${userId}`),
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
    return res.status(400).json({ error: 'Некорректный или устаревший запрос авторизации' });
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
    return res.status(502).json({ error: 'Не удалось получить токен Spotify' });
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
  await invalidateUserCaches(finalUserId);

  const authToken = await issueAuthToken(finalUserId);
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
    return res.status(400).json({ error: 'Недопустимый адрес возврата' });
  }

  const intentId = crypto.randomBytes(16).toString('hex');
  await redisSet(linkIntentKey(intentId), { userId, returnTo }, LINK_INTENT_TTL_SECONDS);

  res.json({ state: intentId, expiresInSeconds: LINK_INTENT_TTL_SECONDS });
});

const getMe = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const userData = await getOrSet(`db:user-profile:${userId}`, 'me', 300, async () => {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { spotifyUser: true },
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
      include: { user: true },
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
    return res.status(404).json({ error: 'Пользователь не найден' });
  }

  const needsToken = req.authVia === 'session' && req.query.needToken === '1';
  if (needsToken) {
    try {
      const authToken = await issueAuthToken(userId);
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
    if (err.statusCode === 403) return res.status(403).json({ error: 'Email в Google-аккаунте не подтверждён' });
    throw err;
  }

  await loginAsUser(req, user.id);
  await invalidateUserCaches(user.id);

  const authToken = await issueAuthToken(user.id);

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

const getSettings = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const settings = await getOrSet(`db:user-settings:${userId}`, 'settings', 300, async () => {
    return prisma.user.findUnique({
      where: { id: userId },
      select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true, isSearchHidden: true },
    });
  });

  if (!settings) return res.status(404).json({ error: 'Пользователь не найден' });

  res.json(settings);
});

const updateSettings = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const dataToUpdate = updateSettingsSchema.parse(req.body);

  const updated = await prisma.user.update({
    where: { id: userId },
    data: dataToUpdate,
    select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true, isSearchHidden: true },
  });

  await invalidateUserCaches(userId);
  res.json(updated);
});

const updateProfile = asyncHandler(async (req, res) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

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
    return res.status(400).json({ error: 'Некорректный или устаревший запрос авторизации' });
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
  if (!id_token) return res.status(502).json({ error: 'Google не вернул id_token' });

  const ticket = await googleClient.verifyIdToken({
    idToken: id_token,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();

  let user;
  try {
    user = await upsertGoogleUser(payload);
  } catch (err) {
    if (err.statusCode === 403) return res.status(403).json({ error: 'Email в Google-аккаунте не подтверждён' });
    throw err;
  }

  await loginAsUser(req, user.id);
  await invalidateUserCaches(user.id);

  const authToken = await issueAuthToken(user.id);
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
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  upload(req, res, async (err) => {
    if (err) {
      const message = err.message?.includes('Неподдерживаемый формат')
        ? err.message
        : `Ошибка загрузки файла: ${err.message}`;
      return res.status(400).json({ error: message });
    }
    if (!req.file) {
      return res.status(400).json({
        error: 'Файл не выбран или имеет неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
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

      await safeDeleteOldAvatar(oldUser?.customAvatarUrl, req.file.filename);

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
      res.status(500).json({ error: 'Ошибка сохранения аватарки' });
    }
  });
};

async function safeDeleteOldAvatar(oldAvatarUrl, currentFilename) {
  if (!oldAvatarUrl) return;
  try {
    const oldName = path.basename(new URL(oldAvatarUrl).pathname);
    if (!oldName || oldName === currentFilename) return;

    const resolved = path.resolve(AVATARS_DIR, oldName);
    if (resolved !== path.join(AVATARS_DIR, oldName)) return;
    if (!resolved.startsWith(AVATARS_DIR + path.sep)) return;

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
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

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
      const fileName = path.basename(user.customAvatarUrl);
      const resolved = path.resolve(AVATARS_DIR, fileName);
      if (resolved.startsWith(AVATARS_DIR)) {
        await fs.promises.unlink(resolved).catch(() => {});
      }
    } catch (err) {
      logger.warn({ err, userId }, 'Не удалось удалить файл аватара');
    }
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
  const limit = Math.min(Number(req.query.limit) || 50, 200);

  const rows = await prisma.playHistory.findMany({
    where: { userId },
    orderBy: { playedAt: 'desc' },
    take: limit * 4,
    select: { spotifyUri: true, trackName: true, artistName: true, playedAt: true },
  });

  const seen = new Set();
  const unique = [];
  for (const row of rows) {
    if (seen.has(row.spotifyUri)) continue;
    seen.add(row.spotifyUri);
    unique.push(row);
    if (unique.length >= limit) break;
  }

  res.json(unique);
});

const clearPlayHistory = asyncHandler(async (req, res) => {
  const userId = req.userId;
  const { count } = await prisma.playHistory.deleteMany({ where: { userId } });

  logger.info({ userId, count }, 'Play history cleared');
  res.json({ message: 'История очищена', removed: count });
});

module.exports = {
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