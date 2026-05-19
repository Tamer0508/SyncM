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

  const returnTo = stateObj.returnTo || req.query.returnTo || '';
  const stateForSpotify = Buffer.from(JSON.stringify({ returnTo, userId: stateObj.userId || req.session.userId })).toString('base64');

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
    let pendingUserId = null;
    if (state) {
      try {
        const decoded = Buffer.from(state, 'base64').toString('utf8');
        const parsed = JSON.parse(decoded);
        returnTo = parsed.returnTo;
        pendingUserId = parsed.userId;
      } catch (e) {}
    }

    const userId = pendingUserId || req.session.userId;

    const spotifyAccount = await prisma.spotifyAccount.upsert({
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

    req.session.userId = spotifyAccount.userId || spotifyAccount.id;
    await req.session.save();

    const cookie = `connect.sid=${req.sessionID}`;
    if (returnTo) {
      const joiner = returnTo.includes('?') ? '&' : '?';
      return res.redirect(`${returnTo}${joiner}auth_done=1&token=${req.session.userId}&cookie=${encodeURIComponent(cookie)}`);
    }

    res.json({ message: 'Spotify connected', userId: req.session.userId });
  } catch (error) {
    res.status(500).json({ error: 'OAuth error' });
  }
};

const getMe = async (req, res) => {
  const userId = req.session?.userId;
  if (!userId) return res.status(401).json({ error: 'Not authorized' });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { spotifyAccount: true },
  });

  if (user) {
    return res.json({
      id: user.id,
      displayName: user.username,
      email: user.email,
      avatarUrl: user.spotifyAccount?.avatarUrl || null,
      spotifyConnected: !!user.spotifyAccount,
    });
  }

  // Fallback for direct spotify login without full User profile
  const spotAccount = await prisma.spotifyAccount.findUnique({
    where: { id: userId },
    include: { user: true }
  });

  if (spotAccount) {
    return res.json({
      id: spotAccount.userId || spotAccount.id,
      displayName: spotAccount.user?.username || spotAccount.displayName,
      avatarUrl: spotAccount.avatarUrl,
      spotifyConnected: true,
    });
  }

  res.status(401).json({ error: 'User not found' });
};

const googleAuth = async (req, res) => {
  const { idToken } = req.body;
  try {
    const ticket = await googleClient.verifyIdToken({ idToken, audience: process.env.GOOGLE_CLIENT_ID });
    const { email, name } = ticket.getPayload();

    const user = await prisma.user.upsert({
      where: { email },
      update: { username: name },
      create: { username: name, email, passwordHash: '' },
    });

    req.session.userId = user.id;
    await req.session.save();
    res.json({ message: 'Logged in with Google', user });
  } catch (error) {
    res.status(401).json({ error: 'Invalid Google token' });
  }
};

const logout = (req, res) => {
  req.session.destroy();
  res.json({ message: 'Logged out' });
};

module.exports = { login, callback, getMe, logout, googleAuth };
