const axios = require('axios');
const prisma = require('../db/prisma');
const { OAuth2Client } = require('google-auth-library');

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

    // Создаем или обновляем Spotify-аккаунт и связываем с User
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
      user: {
        id: req.session.userId,
        displayName: spotifyUser.displayName,
        spotifyConnected: true,
      },
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
    if (auth?.startsWith('Bearer ')) {
      userId = auth.replace('Bearer ', '');
    }
  }

  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  // Ищем User вместе с привязанным Spotify-аккаунтом
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

  // Fallback: если userId — это ID SpotifyUser (legacy)
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
      isFriendsHidden: user.isFriendsHidden,
      isActivityHidden: user.isActivityHidden,
      isOnlineHidden: user.isOnlineHidden,
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
    const email = payload.email;
    const name = payload.name;

    const user = await prisma.user.upsert({
      where: { email },
      update: { username: name },
      create: {
        username: name,
        email,
        passwordHash: '',
      },
    });

    req.session.userId = user.id;
    await req.session.save();

    res.json({
      message: 'Logged in with Google',
      user: {
        id: user.id,
        displayName: user.username,
        email: user.email,
        spotifyConnected: false,
      },
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

// Получить настройки приватности пользователя
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
      select: {
        isOnlineHidden: true,
        isFriendsHidden: true,
        isActivityHidden: true,
      },
    });
    if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

    res.json({
      isOnlineHidden: user.isOnlineHidden,
      isFriendsHidden: user.isFriendsHidden,
      isActivityHidden: user.isActivityHidden,
    });
  } catch (error) {
    console.error('Get settings error:', error);
    res.status(500).json({ error: 'Ошибка получения настроек' });
  }
};

// Обновить настройки приватности
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
      select: {
        isOnlineHidden: true,
        isFriendsHidden: true,
        isActivityHidden: true,
      },
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
  if (typeof username === 'string' && username.trim().length > 0) {
    if (username.trim().length < 2) return res.status(400).json({ error: 'Имя должно содержать минимум 2 символа' });
    dataToUpdate.username = username.trim();
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

// POST /auth/google-web — редирект на Google OAuth для Windows/Desktop
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

    const user = await prisma.user.upsert({
      where: { email: payload.email },
      update: { username: payload.name },
      create: { username: payload.name, email: payload.email, passwordHash: '' },
    });

    req.session.userId = user.id;
    await req.session.save();

    const cookie = `connect.sid=${req.sessionID}`;
    const token = user.id;

    if (returnTo) {
      const joiner = returnTo.includes('?') ? '&' : '?';
      return res.redirect(
        `${returnTo}${joiner}auth_done=1&token=${token}&cookie=${encodeURIComponent(cookie)}`
      );
    }

    res.json({
      message: 'Logged in with Google',
      user: { id: user.id, displayName: user.username, email: user.email },
      cookie,
    });
  } catch (error) {
    console.error('Google web callback error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка авторизации Google' });
  }
};

module.exports = { login, callback, getMe, logout, googleAuth, getSettings, updateSettings, updateProfile, googleWebLogin, googleWebCallback };
