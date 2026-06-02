require('dotenv').config();
require('./infrastructure/redis'); 

const { rateLimitMiddleware } = require('./infrastructure/rateLimiter');
const express = require('express');
const cors = require('cors');
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
const setupSocket = require('./socket');

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
`).then(() => console.log("Session table ready"))
  .catch(err => console.error("Session table error:", err));

const app = express();
app.set('trust proxy', 1);
const httpServer = createServer(app);

// СОЗДАЁМ io ПРАВИЛЬНО:
const io = new Server(httpServer, {
  cors: { origin: '*' }
});

app.use(cors({
  origin: true,
  credentials: true,
  allowedHeaders: ['Content-Type', 'Cookie', 'Authorization'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));

app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));
app.use(express.json());

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

// Подключаем твой setupSocket
setupSocket(io);

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error.message);
});

async function shutdown(signal) {
  console.log(`Received ${signal || 'shutdown'} - shutting down gracefully...`);

  // Force exit after 10 seconds
  const forceTimeout = setTimeout(() => {
    console.error('Could not close connections in time, forcing shutdown');
    process.exit(1);
  }, 10000);

  try {
    // Stop accepting new connections
    await new Promise((resolve) => {
      httpServer.close((err) => {
        if (err) console.error('HTTP server close error:', err);
        else console.log('HTTP server closed');
        resolve();
      });
    });
  } catch (err) {
    console.error('Error while closing HTTP server:', err?.message || err);
  }

  try {
    // Close socket.io if present
    if (io && typeof io.close === 'function') {
      try {
        io.close();
        console.log('Socket.io closed');
      } catch (e) {
        console.error('Error closing socket.io:', e?.message || e);
      }
    }
  } catch (e) {}

  try {
    const prisma = require('./db/prisma');
    await prisma.$disconnect();
    console.log('Prisma disconnected');
  } catch (err) {
    console.error('Prisma disconnect error:', err?.message || err);
  }

  try {
    const redisModule = require('./infrastructure/redis');
    if (redisModule && redisModule.redisClient) {
      await redisModule.redisClient.quit().catch(() => {});
      console.log('Redis disconnected');
    }
  } catch (err) {
    console.error('Redis quit error:', err?.message || err);
  }

  clearTimeout(forceTimeout);
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});