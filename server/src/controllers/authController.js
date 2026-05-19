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
      avatarUrl: user.spotifyUser?.avatarUrl || null,
      spotifyConnected: !!user.spotifyUser,
      spotifyId: user.spotifyUser?.spotifyId || null,
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

module.exports = { login, callback, getMe, logout, googleAuth, getSettings, updateSettings };
