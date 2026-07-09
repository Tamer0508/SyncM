require('dotenv').config();
require('./infrastructure/redis'); 

const { rateLimitMiddleware } = require('./infrastructure/rateLimiter');
const express = require('express');
const cors = require('cors');
const logger = require('./infrastructure/logger');
const pinoHttp = require('pino-http');
const requestId = require('./middleware/requestId');
const session = require('express-session');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { Pool } = require('pg');
const pgSession = require('connect-pg-simple')(session);
const path = require('path');

const authRoutes = require('./routes/auth');
const friendsRoutes = require('./routes/friends'); 
const sessionRoutes = require('./routes/sessions'); 
const spotifyRoutes = require('./routes/spotify');
const playlistRoutes = require('./routes/playlists');
const healthRoutes = require('./routes/health');
const setupSocketModule = require('./socket');
const { closeQueues } = require('./infrastructure/queue');

// Правильный импорт setupSocket и closeSocket
const setupSocket = setupSocketModule.setupSocket || setupSocketModule;
const { closeSocket } = setupSocketModule;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

pool.query(`
  CREATE TABLE IF NOT EXISTS "session" (
    "sid" varchar NOT NULL COLLATE "default",
    "sess" json NOT NULL,
    "expire" timestamp(6) NOT NULL,
    CONSTRAINT "session_pkey" PRIMARY KEY ("sid")
  )
`).then(() => logger.info('Session table ready'))
  .catch(err => logger.error('Session table error:', err));

const app = express();
app.set('trust proxy', 1);
const httpServer = createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin: true,
    credentials: true
  },
  // pingInterval 10с + pingTimeout 20с. Раньше стояло 5с/5с для быстрого
  // детекта обрыва, но 5с pingTimeout слишком мало: при высоком RTT
  // (мобильный интернет) сервер рвал свежее соединение, не дождавшись
  // ping-ответа. Presence детектится чуть медленнее, зато соединение
  // стабильное.
  pingInterval: 10000,
  pingTimeout: 20000,
});

global.io = io;

app.use(cors({
  origin: true,
  credentials: true,
  allowedHeaders: ['Content-Type', 'Cookie', 'Authorization', 'Idempotency-Key'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));

app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));
app.use(express.json());

app.use(requestId);
app.use(pinoHttp({
  logger,
  customLogLevel: (res, err) => {
    if (res.statusCode >= 500 || err) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  }
}));

app.use(session({
  store: new pgSession({
    pool: pool, 
    tableName: 'session', 
  }),
  secret: process.env.SESSION_SECRET || 'your-secret-key',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    sameSite: process.env.NODE_ENV === 'production' ? 'none' : 'lax',
    httpOnly: true,
    maxAge: 7 * 24 * 60 * 60 * 1000
  }
}));

app.use((req, res, next) => {
  try {
    const auth = req.headers.authorization;
    const userId = req.user?.id || req.session?.userId || (auth && auth.startsWith('Bearer ') ? auth.replace('Bearer ', '') : null);
    req.log = (req.log || logger).child({ requestId: req.id || null, userId: userId || null });
  } catch (e) {
    req.log = req.log || logger;
  }
  next();
});

app.use(rateLimitMiddleware(100, 60));

app.use('/auth', authRoutes);
app.use('/friends', friendsRoutes);
app.use('/sessions', sessionRoutes);
app.use('/spotify', spotifyRoutes);
app.use('/playlists', playlistRoutes);
app.use('/health', healthRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'SyncM server is running' });
});

setupSocket(io);

process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled Rejection');
});

process.on('uncaughtException', (error) => {
  logger.error({ err: error }, 'Uncaught Exception');
});

async function shutdown(signal) {
  logger.info({ signal }, 'Received shutdown signal, shutting down gracefully...');

  const forceTimeout = setTimeout(() => {
    logger.error('Could not close connections in time, forcing shutdown');
    process.exit(1);
  }, 10000);

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
    logger.info('BullMQ queues closed');
  } catch (err) {
    logger.error({ err }, 'Error closing BullMQ queues');
  }

  try {
    await closeSocket();  // ← используем функцию из socket.js
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
    if (redisModule && redisModule.redisClient) {
      await redisModule.redisClient.quit();
      logger.info('Redis disconnected');
    }
  } catch (err) {
    logger.error({ err }, 'Redis quit error');
  }

  clearTimeout(forceTimeout);
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  logger.info({ port: PORT, env: process.env.NODE_ENV }, 'Server running');
});