const axios = require('axios');
const prisma = require('../db/prisma');
const { OAuth2Client } = require('google-auth-library');
const crypto = require('crypto');

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI = process.env.SPOTIFY_REDIRECT_URI;

const login = async (req, res) => {
  const scopes = [
    'user-read-private',
    'user-read-email',
    'playlist-read-private',
    'playlist-read-collaborative',
    'playlist-modify-public',
    'playlist-modify-private',
    'user-library-read',
    'streaming',
    'user-modify-playback-state',
    'user-read-playback-state',
  ].join('%20');

  let stateObj = {};
  if (req.query.state) {
    try {
      const decoded = Buffer.from(req.query.state, 'base64').toString('utf8');
      stateObj = JSON.parse(decoded);
    } catch (e) {}
  }

  if (stateObj.userId) {
    req.session.pendingLinkUserId = stateObj.userId;
    await req.session.save();
  }

  const returnTo = stateObj.returnTo || req.query.returnTo || '';
  const stateForSpotify = Buffer.from(JSON.stringify({ returnTo, userId: stateObj.userId })).toString('base64');

  const url = `https://accounts.spotify.com/authorize` +
    `?response_type=code` +
    `&client_id=${CLIENT_ID}` +
    `&scope=${scopes}` +
    `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
    `&state=${encodeURIComponent(stateForSpotify)}` +
    `&show_dialog=true`;

  res.redirect(url);
};

const callback = async (req, res) => {
  const { code, state } = req.query;

  try {
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

    const profileResponse = await axios.get('https://api.spotify.com/v1/me', {
      headers: { Authorization: `Bearer ${access_token}` },
    });

    const profile = profileResponse.data;

    let returnTo = null;
    let pendingLinkUserId = null;

    if (state) {
      try {
        const decoded = Buffer.from(state, 'base64').toString('utf8');
        const parsed = JSON.parse(decoded);
        returnTo = parsed?.returnTo;
        pendingLinkUserId = parsed?.userId;
      } catch (_) {}
    }

    const userId = pendingLinkUserId || req.session?.userId;

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

    req.session.userId = spotifyUser.userId || spotifyUser.id;
    await req.session.save();

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
  } catch (error) {
    console.error('OAuth error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка авторизации Spotify' });
  }
};

const getMe = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { spotifyUser: true },
  });

  if (user) {
    return res.json({
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
    });
  }

  const spotifyUser = await prisma.spotifyUser.findUnique({
    where: { id: userId },
    include: { user: true },
  });

  if (spotifyUser) {
    return res.json({
      id: spotifyUser.userId || spotifyUser.id,
      displayName: spotifyUser.user?.username || spotifyUser.displayName,
      email: spotifyUser.user?.email || spotifyUser.email,
      avatarUrl: spotifyUser.avatarUrl,
      spotifyConnected: true,
      spotifyId: spotifyUser.spotifyId,
      isFriendsHidden: spotifyUser.user?.isFriendsHidden ?? false,
      isActivityHidden: spotifyUser.user?.isActivityHidden ?? false,
      isOnlineHidden: spotifyUser.user?.isOnlineHidden ?? false,
    });
  }

  return res.status(401).json({ error: 'Пользователь не найден' });
};

const googleAuth = async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) return res.status(400).json({ error: 'Missing idToken' });

  try {
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
        data: {
          username: payload.name,
          email: payload.email,
          passwordHash: '',
        },
      });
    }

    req.session.userId = user.id;
    await req.session.save();

    res.json({
      message: 'Logged in with Google',
      user: { id: user.id, displayName: user.username, email: user.email, spotifyConnected: false },
      cookie: `connect.sid=${req.sessionID}`,
    });
  } catch (error) {
    console.error('Google auth error:', error);
    res.status(401).json({ error: 'Invalid token' });
  }
};

const logout = (req, res) => {
  req.session.destroy();
  res.json({ message: 'Вышли из системы' });
};

const getSettings = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true },
    });
    if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
    res.json(user);
  } catch (error) {
    console.error('Get settings error:', error);
    res.status(500).json({ error: 'Ошибка получения настроек' });
  }
};

const updateSettings = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { isOnlineHidden, isFriendsHidden, isActivityHidden } = req.body;

  try {
    const dataToUpdate = {};
    if (typeof isOnlineHidden === 'boolean') dataToUpdate.isOnlineHidden = isOnlineHidden;
    if (typeof isFriendsHidden === 'boolean') dataToUpdate.isFriendsHidden = isFriendsHidden;
    if (typeof isActivityHidden === 'boolean') dataToUpdate.isActivityHidden = isActivityHidden;

    if (Object.keys(dataToUpdate).length === 0) {
      return res.status(400).json({ error: 'Нет данных для обновления' });
    }

    const updated = await prisma.user.update({
      where: { id: userId },
      data: dataToUpdate,
      select: { isOnlineHidden: true, isFriendsHidden: true, isActivityHidden: true },
    });

    res.json(updated);
  } catch (error) {
    console.error('Update settings error:', error);
    res.status(500).json({ error: 'Ошибка обновления настроек' });
  }
};

const updateProfile = async (req, res) => {
  let userId = req.session?.userId;
  if (!userId) {
    const auth = req.headers.authorization;
    if (auth?.startsWith('Bearer ')) userId = auth.replace('Bearer ', '');
  }
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { username, customAvatarUrl } = req.body;
  const dataToUpdate = {};

  if (typeof username === 'string') {
    const trimmed = username.trim();
    if (trimmed.length > 0) {
      if (trimmed.length < 2) return res.status(400).json({ error: 'Имя должно содержать минимум 2 символа' });
      if (trimmed.length > 50) return res.status(400).json({ error: 'Имя должно содержать не более 50 символов' });
      if (/^\s+$/.test(trimmed)) return res.status(400).json({ error: 'Имя не может состоять только из пробелов' });
      if (!/^[\p{L}\p{N} _\-\.]+$/u.test(trimmed)) return res.status(400).json({ error: 'Имя содержит недопустимые символы' });
      dataToUpdate.username = trimmed;
      dataToUpdate.usernameChangedByUser = true;
    }
  }

  if (typeof customAvatarUrl === 'string') {
    dataToUpdate.customAvatarUrl = customAvatarUrl.trim() || null;
  }

  if (Object.keys(dataToUpdate).length === 0) {
    return res.status(400).json({ error: 'Нет данных для обновления' });
  }

  try {
    const updated = await prisma.user.update({
      where: { id: userId },
      data: dataToUpdate,
      select: {
        id: true,
        username: true,
        customAvatarUrl: true,
        spotifyUser: { select: { avatarUrl: true } }
      }
    });

    res.json({
      id: updated.id,
      displayName: updated.username,
      avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
      customAvatarUrl: updated.customAvatarUrl
    });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Ошибка обновления профиля' });
  }
};

// GET /auth/google-web — редирект на Google OAuth для Windows
const googleWebLogin = (req, res) => {
  const returnTo = req.query.returnTo || '';
  const state = Buffer.from(JSON.stringify({ returnTo })).toString('base64');

  const url = 'https://accounts.google.com/o/oauth2/v2/auth' +
    `?client_id=${process.env.GOOGLE_CLIENT_ID}` +
    `&redirect_uri=${encodeURIComponent(process.env.GOOGLE_REDIRECT_URI)}` +
    `&response_type=code` +
    `&scope=email%20profile` +
    `&state=${encodeURIComponent(state)}`;

  res.redirect(url);
};

// GET /auth/google-callback — обработка ответа от Google
const googleWebCallback = async (req, res) => {
  const { code, state } = req.query;
  if (!code) return res.status(400).json({ error: 'Missing code' });

  let returnTo = null;
  try {
    const decoded = Buffer.from(state, 'base64').toString('utf8');
    returnTo = JSON.parse(decoded)?.returnTo;
  } catch (_) {}

  try {
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
        data: {
          username: payload.name,
          email: payload.email,
          passwordHash: '',
        },
      });
    }

    req.session.userId = user.id;
    await req.session.save();

    const cookie = `connect.sid=${req.sessionID}`;
    const token = user.id;

    // Сохраняем для polling из Flutter на Windows
    const pendingTokens = global.pendingTokens || (global.pendingTokens = new Map());
    const tempToken = crypto.randomBytes(16).toString('hex');
    pendingTokens.set(tempToken, { userId: user.id, cookie });
    setTimeout(() => pendingTokens.delete(tempToken), 5 * 60 * 1000);

    if (returnTo && !returnTo.startsWith('syncm://')) {
      const joiner = returnTo.includes('?') ? '&' : '?';
      return res.redirect(
        `${returnTo}${joiner}auth_done=1&token=${token}&cookie=${encodeURIComponent(cookie)}`
      );
    }

    // Для Windows — страница успеха с кодом для ввода в приложение
    return res.send(`
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
          <h2>✅ Вход выполнен!</h2>
          <p>Введите этот код в приложении SyncM:</p>
          <code>${tempToken}</code>
          <p>Код действителен 5 минут.</p>
        </body>
      </html>
    `);
  } catch (error) {
    console.error('Google web callback error:', error.response?.data || error.message);
    return res.status(500).json({ error: 'Ошибка авторизации Google' });
  }
};

const multer = require('multer');
const path = require('path');
const fs = require('fs');

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
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, allowed.includes(ext));
  }
}).single('avatar');

const uploadAvatar = async (req, res) => {
  upload(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'Файл не загружен' });
    }

    const userId = req.session?.userId || req.headers.authorization?.replace('Bearer ', '');
    if (!userId) return res.status(401).json({ error: 'Не авторизован' });

    // Формируем URL
    const baseUrl = process.env.BASE_URL || `https://${req.get('host')}`;
    const avatarUrl = `${baseUrl}/uploads/avatars/${req.file.filename}`;

    try {
      const oldUser = await prisma.user.findUnique({ where: { id: userId }, select: { customAvatarUrl: true } });
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
          spotifyUser: { select: { avatarUrl: true } }
        }
      });

      res.json({
        id: updated.id,
        displayName: updated.username,
        avatarUrl: updated.customAvatarUrl || updated.spotifyUser?.avatarUrl || null,
        customAvatarUrl: updated.customAvatarUrl
      });
    } catch (error) {
      console.error('Upload avatar error:', error);
      res.status(500).json({ error: 'Ошибка сохранения аватарки' });
    }
  });
};

// GET /auth/check-pending?token=xxx — polling для Windows
const checkPendingAuth = (req, res) => {
  const { token } = req.query;
  const pendingTokens = global.pendingTokens || new Map();
  const data = pendingTokens.get(token);
  if (data) {
    pendingTokens.delete(token);
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