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
    'streaming',
    'user-modify-playback-state',
    'user-read-playback-state',
  ].join('%20');

  let stateObj = {};
  if (req.query.state) {
    try {
      const decoded = Buffer.from(req.query.state, 'base64').toString('utf8');
      stateObj = JSON.parse(decoded);
    } catch (e) {
      // старый формат или просто строка — игнорируем
    }
  }

  // Если пришёл userId, сохраним его в сессии временно
  if (stateObj.userId) {
    req.session.pendingLinkUserId = stateObj.userId;
    await req.session.save();
  }

  const returnTo = stateObj.returnTo || req.query.returnTo || '';
  // Для Spotify передаём returnTo в state (base64 JSON)
  const stateForSpotify = Buffer.from(JSON.stringify({ returnTo })).toString('base64');

  const url = `https://accounts.spotify.com/authorize` +
    `?response_type=code` +
    `&client_id=${CLIENT_ID}` +
    `&scope=${scopes}` +
    `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
    `&state=${encodeURIComponent(stateForSpotify)}`;

  res.redirect(url);
};

const callback = async (req, res) => {
  const { code } = req.query;

  try {
    // Получаем токены
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

    // Получаем данные пользователя из Spotify
    const profileResponse = await axios.get('https://api.spotify.com/v1/me', {
      headers: { Authorization: `Bearer ${access_token}` },
    });

    const profile = profileResponse.data;

    // Получаем userId, который нужно привязать (из временного поля сессии)
    const pendingLinkUserId = req.session.pendingLinkUserId;
    delete req.session.pendingLinkUserId;

    let appUserId = pendingLinkUserId;
    if (!appUserId && req.session?.userId) {
      const sessionAppUser = await prisma.appUser.findUnique({ where: { id: req.session.userId } });
      if (sessionAppUser) appUserId = sessionAppUser.id;
    }

    // Проверяем, есть ли уже такой Spotify-пользователь
    const existingUser = await prisma.user.findUnique({
      where: { spotifyId: profile.id },
      include: { appUser: true },
    });

    // Если у существующего пользователя уже есть appUserId, используем его
    if (existingUser?.appUserId) {
      appUserId = existingUser.appUserId;
    }

    // Сохраняем или обновляем пользователя в БД
    const user = await prisma.user.upsert({
      where: { spotifyId: profile.id },
      update: {
        displayName: profile.display_name,
        email: profile.email,
        avatarUrl: profile.images?.[0]?.url || null,
        accessToken: access_token,
        refreshToken: refresh_token,
        appUserId: appUserId || existingUser?.appUserId || undefined,
      },
      create: {
        spotifyId: profile.id,
        displayName: profile.display_name,
        email: profile.email,
        avatarUrl: profile.images?.[0]?.url || null,
        accessToken: access_token,
        refreshToken: refresh_token,
        appUserId: appUserId || undefined,
      },
    });

    // Если appUserId был определён, но по какой-то причине не записался, обновляем
    if (appUserId && !user.appUserId) {
      await prisma.user.update({
        where: { id: user.id },
        data: { appUserId: appUserId },
      });
    }

    // Обновляем сессию: userId должен быть appUserId (если есть) или spotify user id
    req.session.userId = appUserId || user.id;

    // Получаем returnTo из state, который вернул Spotify
    let returnTo = null;
    if (req.query.state) {
      try {
        const decoded = Buffer.from(req.query.state, 'base64').toString('utf8');
        const parsed = JSON.parse(decoded);
        returnTo = parsed?.returnTo ?? null;
      } catch (_) {
        // игнорируем
      }
    }

    await req.session.save();

    const cookie = `connect.sid=${req.sessionID}`;

    if (returnTo) {
      if (returnTo.startsWith('myapp://')) {
        return res.redirect(
          `${returnTo}?token=${encodeURIComponent(user.id)}&cookie=${encodeURIComponent(cookie)}`
        );
      }

      const joiner = returnTo.includes('?') ? '&' : '?';
      return res.redirect(
        `${returnTo}${joiner}auth_done=1&token=${encodeURIComponent(user.id)}&cookie=${encodeURIComponent(cookie)}`
      );
    }

    res.json({
      message: 'Авторизация успешна',
      user: {
        id: user.id,
        displayName: user.displayName,
        email: user.email,
        avatarUrl: user.avatarUrl,
      },
      cookie,
    });
  } catch (error) {
    console.error('OAuth error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Ошибка авторизации' });
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
  if (!userId) {
    return res.status(401).json({ error: 'Не авторизован' });
  }

  const appUser = await prisma.appUser.findUnique({
    where: { id: userId },
    include: { spotifyUser: true } // в схеме если че связь называется spotifyUser
  });
  if (appUser) {
    return res.json({
      id: appUser.id,
      displayName: appUser.username,
      email: appUser.email,
      avatarUrl: appUser.spotifyUser?.avatarUrl || null,
      spotifyConnected: !!appUser.spotifyUser,
    });
  }

  const spotifyUser = await prisma.user.findUnique({
    where: { id: userId },
    include: { appUser: true }
  });
  if (spotifyUser) {
    return res.json({
      id: spotifyUser.appUserId || spotifyUser.id,
      displayName: spotifyUser.displayName,
      email: spotifyUser.email,
      avatarUrl: spotifyUser.avatarUrl,
      spotifyConnected: true,
    });
  }

  return res.status(401).json({ error: 'Не авторизован' });
};

const googleAuth = async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) {
    return res.status(400).json({ error: 'Missing idToken' });
  }

  try {
    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: process.env.GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    const email = payload.email;
    const name = payload.name;

    let appUser = await prisma.appUser.findUnique({ where: { email } });

    if (!appUser) {
      appUser = await prisma.appUser.create({
        data: {
          username: name,
          email: email,
          passwordHash: '',
        },
      });
    }

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

module.exports = { login, callback, getMe, logout, googleAuth };