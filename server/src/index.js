require('dotenv').config();
const express = require('express');
const cors = require('cors');
const session = require('express-session');
const { createServer } = require('http');
const { Pool } = require('pg');
const pgSession = require('connect-pg-simple')(session);

const authRoutes = require('./routes/auth');
const friendsRoutes = require('./routes/friends'); 
const sessionRoutes = require('./routes/sessions'); 
const spotifyRoutes = require('./routes/spotify');
const playlistRoutes = require('./routes/playlists');
const { setupSocket } = require('./socket'); // Изменили на деструктуризацию

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// Создание таблицы сессий если её нет
pool.query(`
  CREATE TABLE IF NOT EXISTS "session" (
    "sid" varchar NOT NULL COLLATE "default",
    "sess" json NOT NULL,
    "expire" timestamp(6) NOT NULL,
    CONSTRAINT "session_pkey" PRIMARY KEY ("sid")
  )
`).catch(err => console.error("Session table error:", err));

const app = express();
app.set('trust proxy', 1);
const httpServer = createServer(app);

// Инициализация Socket.io через наш сервис
const io = initSocket(httpServer);

app.use(cors({
  origin: true,
  credentials: true,
  allowedHeaders: ['Content-Type', 'Cookie', 'Authorization'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));

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
    maxAge: 7 * 24 * 60 * 60 * 1000 // 7 дней
  }
}));

// Роуты
app.use('/auth', authRoutes);
app.use('/friends', friendsRoutes);
app.use('/sessions', sessionRoutes);
app.use('/spotify', spotifyRoutes);
app.use('/playlists', playlistRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'SyncM server is running' });
});

setupSocket(io); // Инициализируем сокет твоей функцией

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error.message);
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
