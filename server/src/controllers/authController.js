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
  const stateForSpotify = Buffer.from(JSON.stringify({ returnTo })).toString('base64');

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
  const { code } = req.query;

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

    const pendingLinkUserId = req.session.pendingLinkUserId;
    delete req.session.pendingLinkUserId;

    let appUserId = pendingLinkUserId || req.session?.userId;

    const existingSpotifyUser = await prisma.user.findUnique({
      where: { spotifyId: profile.id }
    });

    if (existingSpotifyUser?.app_user_id) {
      appUserId = existingSpotifyUser.app_user_id;
    }

    const user = await prisma.user.upsert({
      where: { spotifyId: profile.id },
      update: {
        displayName: profile.display_name,
        email: profile.email,
        avatarUrl: profile.images?.[0]?.url || null,
        accessToken: access_token,
        refreshToken: refresh_token,
        ...(appUserId ? { app_user_id: appUserId } : {}),
      },
      create: {
        spotifyId: profile.id,
        displayName: profile.display_name,
        email: profile.email,
        avatarUrl: profile.images?.[0]?.url || null,
        accessToken: access_token,
        refreshToken: refresh_token,
        ...(appUserId ? { app_user_id: appUserId } : {}),
      },
    });

    req.session.userId = appUserId || user.id;

    let returnTo = null;
    if (req.query.state) {
      try {
        const decoded = Buffer.from(req.query.state, 'base64').toString('utf8');
        const parsed = JSON.parse(decoded);
        returnTo = parsed?.returnTo ?? null;
      } catch (_) {}
    }

    await req.session.save();
    const cookie = `connect.sid=${req.sessionID}`;

    if (returnTo) {
      if (returnTo.startsWith('myapp://')) {
        return res.redirect(
          `${returnTo}?token=${encodeURIComponent(appUserId || user.id)}&cookie=${encodeURIComponent(cookie)}`
        );
      }
      const joiner = returnTo.includes('?') ? '&' : '?';
      return res.redirect(
        `${returnTo}${joiner}auth_done=1&token=${encodeURIComponent(appUserId || user.id)}&cookie=${encodeURIComponent(cookie)}`
      );
    }

    res.json({
      message: 'Spotify подключен успешно',
      user: {
        id: appUserId || user.id,
        displayName: user.displayName,
        email: user.email,
        avatarUrl: user.avatarUrl,
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

  // Ищем AppUser с привязанным Spotify (поле User согласно схеме Prisma)
  const appUser = await prisma.appUser.findUnique({
    where: { id: userId },
    select: {
      id: true,
      username: true,
      email: true,
      friendsCount: true,
      isOnline: true,
      lastSeenAt: true,
      isFriendsHidden: true,
      isActivityHidden: true,
      isOnlineHidden: true,
      User: { select: { avatarUrl: true, spotifyId: true } }
    }
  });

  if (appUser) {
    return res.json({
      id: appUser.id,
      displayName: appUser.username,
      email: appUser.email,
      avatarUrl: appUser.User?.avatarUrl || null,
      spotifyConnected: !!appUser.User,
      spotifyId: appUser.User?.spotifyId || null,
      isFriendsHidden: appUser.isFriendsHidden,
      isActivityHidden: appUser.isActivityHidden,
      isOnlineHidden: appUser.isOnlineHidden,
    });
  }

  // Если userId — это ID Spotify User (старая сессия без AppUser)
  const spotifyUser = await prisma.user.findUnique({
    where: { id: userId },
    include: { AppUser: true },
  });

  if (spotifyUser) {
    return res.json({
      id: spotifyUser.app_user_id || spotifyUser.id,
      displayName: spotifyUser.AppUser?.username || spotifyUser.displayName,
      email: spotifyUser.AppUser?.email || spotifyUser.email,
      avatarUrl: spotifyUser.avatarUrl,
      spotifyConnected: true,
      spotifyId: spotifyUser.spotifyId,
    });
  }

  return res.status(401).json({ error: 'Пользователь не найден' });
};

const getUserId = (req) => {
  if (req.session?.userId) return req.session.userId;
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) return auth.replace('Bearer ', '');
  return null;
};

const getSettings = async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  try {
    const user = await prisma.appUser.findUnique({
      where: { id: userId },
      select: {
        isFriendsHidden: true,
        isActivityHidden: true,
        isOnlineHidden: true,
      }
    });
    if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
    res.json(user);
  } catch (error) {
    console.error('Get settings error:', error);
    res.status(500).json({ error: 'Ошибка получения настроек' });
  }
};

const updateSettings = async (req, res) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ error: 'Не авторизован' });

  const { isFriendsHidden, isActivityHidden, isOnlineHidden } = req.body;
  const data = {};
  if (typeof isFriendsHidden === 'boolean') data.isFriendsHidden = isFriendsHidden;
  if (typeof isActivityHidden === 'boolean') data.isActivityHidden = isActivityHidden;
  if (typeof isOnlineHidden === 'boolean') data.isOnlineHidden = isOnlineHidden;

  if (Object.keys(data).length === 0) {
    return res.status(400).json({ error: 'Нет полей для обновления' });
  }

  try {
    const updated = await prisma.appUser.update({
      where: { id: userId },
      data,
      select: {
        isFriendsHidden: true,
        isActivityHidden: true,
        isOnlineHidden: true,
      }
    });
    res.json(updated);
  } catch (error) {
    console.error('Update settings error:', error);
    res.status(500).json({ error: 'Ошибка обновления настроек' });
  }
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

    // upsert вместо findUnique + create — избегаем race condition и дублей
    const appUser = await prisma.appUser.upsert({
      where: { email },
      update: { username: name }, // обновляем имя если изменилось
      create: {
        username: name,
        email,
        passwordHash: '',
      },
    });

    req.session.userId = appUser.id;
    req.session.save((err) => {
      if (err) {
        console.error('Session save error:', err);
        return res.status(500).json({ error: 'Ошибка сохранения сессии' });
      }
      res.json({
        message: 'Logged in with Google',
        user: {
          id: appUser.id,
          displayName: appUser.username,
          email: appUser.email,
          avatarUrl: null,
          spotifyConnected: false,
        },
        cookie: `connect.sid=${req.sessionID}`,
      });
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

module.exports = { login, callback, getMe, logout, googleAuth, getSettings, updateSettings };