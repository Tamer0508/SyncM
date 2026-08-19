require('dotenv').config();
require('./infrastructure/redis');

const { rateLimitMiddleware } = require('./infrastructure/rateLimiter');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const logger = require('./infrastructure/logger');
const pinoHttp = require('pino-http');
const requestId = require('./middleware/requestId');
const session = require('express-session');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { Pool } = require('pg');
const pgSession = require('connect-pg-simple')(session);
const path = require('path');
const { ZodError } = require('zod');

const authRoutes = require('./routes/auth');
const friendsRoutes = require('./routes/friends');
const sessionRoutes = require('./routes/sessions');
const spotifyRoutes = require('./routes/spotify');
const playlistRoutes = require('./routes/playlists');
const healthRoutes = require('./routes/health');
const legalRoutes = require('./routes/legal');
const setupSocketModule = require('./socket');
const { closeQueues, initQueues } = require('./infrastructure/queue');

const setupSocket = setupSocketModule.setupSocket || setupSocketModule;
const { closeSocket } = setupSocketModule;

if (!process.env.SESSION_SECRET) {
  throw new Error('КРИТИЧЕСКАЯ ОШИБКА: SESSION_SECRET не задан в .env');
}

const allowedOrigins = (process.env.CLIENT_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

if (process.env.NODE_ENV === 'production' && allowedOrigins.length === 0) {
  throw new Error('КРИТИЧЕСКАЯ ОШИБКА: CLIENT_ORIGINS не задан в .env (нужен хотя бы один разрешённый origin)');
}

const LOOPBACK_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;
const allowLoopbackOrigins = process.env.NODE_ENV !== 'production';

function corsOriginCheck(origin, callback) {
  if (!origin) return callback(null, true);
  if (allowedOrigins.includes(origin)) return callback(null, true);
  if (allowLoopbackOrigins && LOOPBACK_ORIGIN.test(origin)) return callback(null, true);

  logger.warn({ origin }, 'CORS: origin not allowed');
  const err = new Error(`Origin ${origin} not allowed by CORS`);
  err.statusCode = 403;
  return callback(err);
}

const googleVars = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REDIRECT_URI'];
const missingGoogleVars = googleVars.filter((name) => !process.env[name]);
if (missingGoogleVars.length > 0) {
  logger.warn(
    { missing: missingGoogleVars },
    'Вход через Google в браузере работать не будет: не заданы переменные окружения'
  );
}

const spotifyVars = ['SPOTIFY_CLIENT_ID', 'SPOTIFY_CLIENT_SECRET', 'SPOTIFY_REDIRECT_URI'];
const missingSpotifyVars = spotifyVars.filter((name) => !process.env[name]);
if (missingSpotifyVars.length > 0) {
  logger.warn(
    { missing: missingSpotifyVars },
    'Подключение Spotify работать не будет: не заданы переменные окружения'
  );
}

initQueues();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

const app = express();
app.set('trust proxy', 1);
app.disable('x-powered-by');

app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' }, // чтобы /uploads работали с другого origin
}));

const httpServer = createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin: corsOriginCheck,
    credentials: true,
  },
  pingInterval: 10000,
  pingTimeout: 20000,
});

app.use(cors({
  origin: corsOriginCheck,
  credentials: true,
  allowedHeaders: ['Content-Type', 'Cookie', 'Authorization', 'Idempotency-Key'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));

app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));
app.use(express.json({ limit: '1mb' }));

app.use(requestId);
app.use(pinoHttp({
  logger,
  genReqId: (req) => req.id,
  customLogLevel: (res, err) => {
    if (res.statusCode >= 500 || err) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  },
}));

const sessionMiddleware = session({
  store: new pgSession({
    pool: pool,
    tableName: 'session',
  }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    sameSite: process.env.NODE_ENV === 'production' ? 'none' : 'lax',
    httpOnly: true,
    maxAge: 7 * 24 * 60 * 60 * 1000,
  },
});
app.use(sessionMiddleware);

io.engine.use(sessionMiddleware);

app.use((req, res, next) => {
  try {
    const userId = req.userId || req.session?.userId || null;
    req.log = (req.log || logger).child({
      userId: userId || undefined,
      traceId: req.traceId,
      spanId: req.spanId,
      parentSpanId: req.parentSpanId,
    });
  } catch (e) {
    req.log = req.log || logger;
  }
  next();
});

app.use('/health', healthRoutes);

app.use('/legal', legalRoutes);

app.use(rateLimitMiddleware(100, 60, {
  keyGenerator: (req) => {
    const userId = req.session?.userId;
    return userId ? `rate:global:user:${userId}` : `rate:global:ip:${req.ip}`;
  },
}));


// Маршруты
app.use('/auth', authRoutes);
app.use('/friends', friendsRoutes);
app.use('/sessions', sessionRoutes);
app.use('/spotify', spotifyRoutes);
app.use('/playlists', playlistRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'SyncM server is running' });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Не найдено' });
});

app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);

  const log = req.log || logger;

  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'Ошибка валидации',
      details: err.issues.map((e) => ({ path: e.path.join('.'), message: e.message })),
    });
  }

  if (err.code === 'P2025') {
    log.warn({ err }, 'Prisma record not found');
    return res.status(404).json({ error: 'Запись не найдена' });
  }
  if (err.code === 'P2002') {
    log.warn({ err }, 'Prisma unique constraint violation');
    return res.status(409).json({ error: 'Такая запись уже существует' });
  }

  const status = err.statusCode || err.status || 500;
  if (status >= 500) {
    log.error({ err }, 'Unhandled request error');
  } else {
    log.warn({ err }, 'Request error');
  }

  res.status(status).json({
    error: status >= 500 ? 'Внутренняя ошибка сервера' : err.message || 'Ошибка запроса',
  });
});

setupSocket(io);

let isShuttingDown = false;

async function shutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.info({ signal }, 'Received shutdown signal, shutting down gracefully...');

  const forceTimeout = setTimeout(() => {
    logger.error('Could not close connections in time, forcing shutdown');
    process.exit(1);
  }, 10000);
  forceTimeout.unref();

  try {
    await new Promise((resolve) => {
      httpServer.close((err) => {
        if (err) logger.error({ err }, 'HTTP server close error');
        else logger.info('HTTP server closed');
        resolve();
      });
    });
  } catch (err) {
    logger.error({ err }, 'Error while closing HTTP server');
  }

  try {
    await closeQueues();
  } catch (err) {
    logger.error({ err }, 'Error closing BullMQ queues');
  }

  try {
    await closeSocket();
    logger.info('Socket.io closed');
  } catch (err) {
    logger.error({ err }, 'Error closing socket.io');
  }

  try {
    const prisma = require('./db/prisma');
    await prisma.$disconnect();
    logger.info('Prisma disconnected');
  } catch (err) {
    logger.error({ err }, 'Prisma disconnect error');
  }

  try {
    const redisModule = require('./infrastructure/redis');
    if (redisModule.clearPendingFetches) {
      redisModule.clearPendingFetches();
    }
    if (redisModule.redisClient) {
      await redisModule.redisClient.quit();
      logger.info('Redis disconnected');
    }
  } catch (err) {
    logger.error({ err }, 'Redis quit error');
  }

  try {
    await pool.end();
    logger.info('Session store pg pool closed');
  } catch (err) {
    logger.error({ err }, 'Session store pg pool close error');
  }

  clearTimeout(forceTimeout);
  process.exit(0);
}

process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled Rejection');
});

process.on('uncaughtException', (error) => {
  logger.fatal({ err: error }, 'Uncaught Exception, shutting down');
  shutdown('uncaughtException').finally(() => process.exit(1));
});

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  logger.info({ port: PORT, env: process.env.NODE_ENV }, 'Server running');
});