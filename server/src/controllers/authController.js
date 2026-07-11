const axios = require('axios');
const prisma = require('../db/prisma');
const { OAuth2Client } = require('google-auth-library');
const crypto = require('crypto');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { z } = require('zod');

const { getOrSet, incrementVersion } = require('../infrastructure/redis');
const logger = require('../infrastructure/logger');
const asyncHandler = require('../utils/asyncHandler');

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI = process.env.SPOTIFY_REDIRECT_URI;

const googleAuthSchema = z.object({
  idToken: z.string().min(1, 'Missing idToken'),
});

const updateSettingsSchema = z.object({
  isOnlineHidden: z.boolean().optional(),
  isFriendsHidden: z.boolean().optional(),
  isActivityHidden: z.boolean().optional(),
}).refine(data => Object.keys(data).length > 0, {
  message: 'Нет данных для обновления',
});

const updateProfileSchema = z.object({
  username: z.string().trim().min(2, 'Имя должно содержать минимум 2 символа')
    .max(50, 'Имя должно содержать не более 50 символов')
    .regex(/^[\p{L}\p{N} _\-\.]+$/u, 'Имя содержит недопустимые символы')
    .optional(),
  customAvatarUrl: z.string().url('Некорректный URL аватарки').optional().nullable(),
}).refine(data => data.username !== undefined || data.customAvatarUrl !== undefined, {
  message: 'Нет данных для обновления',
});

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};


const login = (req, res) => {
  const scopes = [
    'user-read-private', 'user-read-email', 'playlist-read-private',
    'playlist-read-collaborative', 'playlist-modify-public',
    'playlist-modify-private', 'user-library-read', 'streaming',
    'user-modify-playback-state', 'user-read-playback-state',
  ].join('%20');

  let stateObj = {};
  if (req.query.state) {
    try {
      const decoded = Buffer.from(req.query.state, 'base64').toString('utf8');
      stateObj = JSON.parse(decoded);
    } catch (_) {}
  }

  if (stateObj.userId) {
    req.session.pendingLinkUserId = stateObj.userId;
    req.session.save().catch(() => {});
  }

  let returnTo = stateObj.returnTo || req.query.returnTo || '';
  if (returnTo.length > 500) returnTo = returnTo.substring(0, 500);

  const stateForSpotify = Buffer.from(JSON.stringify({
    returnTo,
    userId: stateObj.userId,
  })).toString('base64');

  const url = `https://accounts.spotify.com/authorize` +
    `?response_type=code` +
    `&client_id=${CLIENT_ID}` +
    `&scope=${scopes}` +
    `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
    `&state=${encodeURIComponent(stateForSpotify)}` +
    `&show_dialog=true`;

  res.redirect(url);
};

const callback = asyncHandler(async (req, res) => {
  const { code, state } = req.query;

  // Обмен кода на токены
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
    }
  );

  const { access_token, refresh_token } = tokenResponse.data;

  // Получение профиля
  const profileResponse = await axios.get('https://api.spotify.com/v1/me', {
    headers: { Authorization: `Bearer ${access_token}` },
  });
  const profile = profileResponse.data;

  // Извлечение returnTo из state
  let returnTo = null;
  let pendingLinkUserId = null;
  try {
    const decoded = Buffer.from(state || '', 'base64').toString('utf8');
    const parsed = JSON.parse(decoded);
    returnTo = parsed?.returnTo;
    pendingLinkUserId = parsed?.userId;
  } catch (_) {}

  const userId = pendingLinkUserId || req.session?.userId;

  // Upsert spotifyUser и связь с user
  const spotifyUser = await prisma.spotifyUser.upsert({
    where: { spotifyId: profile.id },
    update: {
      displayName: profile.display_name,
      email: profile.email,
      avatarUrl: profile.images?.[0]?.url || null,
      accessToken: access_token,
      refreshToken: refresh_token,
      ...(userId ? { userId } : {}),
    },
    create: {
      spotifyId: profile.id,
      displayName: profile.display_name,
      email: profile.email,
      avatarUrl: profile.images?.[0]?.url || null,
      accessToken: access_token,
      refreshToken: refresh_token,
      ...(userId ? { userId } : {}),
    },
  });

  let finalUserId = userId;
  if (!finalUserId) {
    const newUser = await prisma.user.create({
      data: {
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

  req.session.userId = finalUserId;
  await req.session.save();

  // Инвалидация кэша
  await incrementVersion();

  const cookie = `connect.sid=${req.sessionID}`;

  if (returnTo) {
    const joiner = returnTo.includes('?') ? '&' : '?';
    const redirectUrl = returnTo.startsWith('myapp://')
      ? `${returnTo}?token=${req.session.userId}&cookie=${encodeURIComponent(cookie)}`
      : `${returnTo}${joiner}auth_done=1&token=${req.session.userId}&cookie=${encodeURIComponent(cookie)}`;
    return res.redirect(redirectUrl);
  }

  res.json({
    message: 'Spotify подключен успешно',
    user: { id: req.session.userId, displayName: spotifyUser.displayName, spotifyConnected: true },
    cookie,
  });
});

const getMe = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:user-profile:${userId}`;
  const userData = await getOrSet(cacheKey, 300, async () => {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { spotifyUser: true },
    });

    if (user) {
      return {
        id: user.id,
        displayName: user.username,
        email: user.email,
        avatarUrl: user.customAvatarUrl || user.spotifyUser?.avatarUrl || null,
        spotifyConnected: !!user.spotifyUser,
        spotifyId: user.spotifyUser?.spotifyId || null,
        isFriendsHidden: user.isFriendsHidden,
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
        displayName: spotifyUser.user?.username || spotifyUser.displayName,
        email: spotifyUser.user?.email || spotifyUser.email,
        avatarUrl: spotifyUser.avatarUrl,
        spotifyConnected: true,
        spotifyId: spotifyUser.spotifyId,
        isFriendsHidden: spotifyUser.user?.isFriendsHidden ?? false,
        isActivityHidden: spotifyUser.user?.isActivityHidden ?? false,
        isOnlineHidden: spotifyUser.user?.isOnlineHidden ?? false,
      };
    }

    return null;
  });

  if (!userData) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }

  res.json(userData);
});

const googleAuth = asyncHandler(async (req, res) => {
  const { idToken } = googleAuthSchema.parse(req.body);

  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();

  let user = await prisma.user.findUnique({ where: { email: payload.email } });
  if (user) {
    if (!user.usernameChangedByUser) {
      user = await prisma.user.update({
        where: { email: payload.email },
        data: { username: payload.name },
      });
    }
  } else {
    user = await prisma.user.create({
      data: { username: payload.name, email: payload.email, passwordHash: '' },
    });
  }

  req.session.userId = user.id;
  await req.session.save();

  await incrementVersion();

  res.json({
    message: 'Logged in with Google',
    user: { id: user.id, displayName: user.username, email: user.email, spotifyConnected: false },
    cookie: `connect.sid=${req.sessionID}`,
  });
});

const logout = asyncHandler(async (req, res) => {
  const userId = req.session?.userId;
  req.session.destroy();
  if (userId) await incrementVersion();
  res.json({ message: 'Вышли из системы' });
});

const getSettings = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const cacheKey = `db:user-settings:${userId}`;
  const settings = await getOrSet(cacheKey, 300, async () => {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true },
    });
    if (!user) throw new Error('Пользователь не найден');
    return user;
  });

  res.json(settings);
});

const updateSettings = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const dataToUpdate = updateSettingsSchema.parse(req.body);

  const updated = await prisma.user.update({
    where: { id: userId },
    data: dataToUpdate,
    select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true },
  });

  await incrementVersion();
  res.json(updated);
});

const updateProfile = asyncHandler(async (req, res) => {
  const userId = getUserId(req);
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

  await incrementVersion();

  res.json({
    id: updated.id,
    displayName: updated.username,
    avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
    customAvatarUrl: updated.customAvatarUrl,
  });
});

const googleWebLogin = (req, res) => {
  let returnTo = req.query.returnTo || '';
  if (returnTo.length > 500) returnTo = returnTo.substring(0, 500);

  const state = Buffer.from(JSON.stringify({ returnTo })).toString('base64');
  const url = 'https://accounts.google.com/o/oauth2/v2/auth' +
    `?client_id=${process.env.GOOGLE_CLIENT_ID}` +
    `&redirect_uri=${encodeURIComponent(process.env.GOOGLE_REDIRECT_URI)}` +
    `&response_type=code` +
    `&scope=email%20profile` +
    `&state=${encodeURIComponent(state)}`;

  res.redirect(url);
};

const googleWebCallback = asyncHandler(async (req, res) => {
  const { code, state } = req.query;
  if (!code) return res.status(400).json({ error: 'Missing code' });

  let returnTo = null;
  try {
    const decoded = Buffer.from(state, 'base64').toString('utf8');
    returnTo = JSON.parse(decoded)?.returnTo;
  } catch (_) {}

  const tokenRes = await axios.post(
    'https://oauth2.googleapis.com/token',
    new URLSearchParams({
      code,
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      redirect_uri: process.env.GOOGLE_REDIRECT_URI,
      grant_type: 'authorization_code',
    }),
    { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }
  );

  const { id_token } = tokenRes.data;
  const ticket = await googleClient.verifyIdToken({
    idToken: id_token,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();

  let user = await prisma.user.findUnique({ where: { email: payload.email } });
  if (user) {
    if (!user.usernameChangedByUser) {
      user = await prisma.user.update({
        where: { email: payload.email },
        data: { username: payload.name },
      });
    }
  } else {
    user = await prisma.user.create({
      data: { username: payload.name, email: payload.email, passwordHash: '' },
    });
  }

  req.session.userId = user.id;
  await req.session.save();

  await incrementVersion();

  const cookie = `connect.sid=${req.sessionID}`;
  const token = user.id;

  // Сохраняем для polling из Flutter на Windows
  if (!global.pendingTokens) global.pendingTokens = new Map();
  const tempToken = crypto.randomBytes(16).toString('hex');
  global.pendingTokens.set(tempToken, { userId: user.id, cookie });
  setTimeout(() => global.pendingTokens.delete(tempToken), 5 * 60 * 1000);

  if (returnTo && !returnTo.startsWith('syncm://')) {
    const joiner = returnTo.includes('?') ? '&' : '?';
    return res.redirect(
      `${returnTo}${joiner}auth_done=1&token=${token}&cookie=${encodeURIComponent(cookie)}`
    );
  }

  // Страница успеха с кодом
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
        <h2> Вход выполнен!</h2>
        <p>Введите этот код в приложении SyncM:</p>
        <code>${tempToken}</code>
        <p>Код действителен 5 минут.</p>
      </body>
    </html>
  `);
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '../../uploads/avatars');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const name = `${req.session.userId || 'unknown'}_${Date.now()}${ext}`;
    cb(null, name);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) cb(null, true);
    else cb(new Error('Неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP'), false);
  },
}).single('avatar');

const uploadAvatar = (req, res) => {
  upload(req, res, async (err) => {
    if (err) {
      const message = err.message?.includes('Неподдерживаемый формат')
        ? err.message
        : 'Ошибка загрузки файла: ' + err.message;
      return res.status(400).json({ error: message });
    }
    if (!req.file) {
      return res.status(400).json({
        error: 'Файл не выбран или имеет неподдерживаемый формат. Разрешены: PNG, JPG, JPEG, GIF, WEBP',
      });
    }

    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    const baseUrl = process.env.BASE_URL || `https://${req.get('host')}`;
    const avatarUrl = `${baseUrl}/uploads/avatars/${req.file.filename}`;

    try {
      const oldUser = await prisma.user.findUnique({
        where: { id: userId },
        select: { customAvatarUrl: true },
      });
      if (oldUser?.customAvatarUrl) {
        const oldPath = path.join(__dirname, '../../', oldUser.customAvatarUrl.replace(baseUrl, ''));
        if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
      }

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

      await incrementVersion();

      res.json({
        id: updated.id,
        displayName: updated.username,
        avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
        customAvatarUrl: updated.customAvatarUrl,
      });
    } catch (error) {
      if (req.log) req.log.error('Upload avatar error:', error);
      res.status(500).json({ error: 'Ошибка сохранения аватарки' });
    }
  });
};

const checkPendingAuth = (req, res) => {
  const { token } = req.query;
  if (!global.pendingTokens) global.pendingTokens = new Map();
  const data = global.pendingTokens.get(token);
  if (data) {
    global.pendingTokens.delete(token);
    return res.json({ success: true, userId: data.userId, cookie: data.cookie });
  }
  res.json({ success: false });
};

module.exports = {
  login,
  callback,
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
};