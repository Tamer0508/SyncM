require('dotenv').config();
const express = require('express');
const cors = require('cors');
const session = require('express-session');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { Pool } = require('pg');

const authRoutes = require('./routes/auth');
const friendsRoutes = require('./routes/friends'); 
const sessionRoutes = require('./routes/sessions'); 
const setupSocket = require('./socket');
const pgSession = require('connect-pg-simple')(session);
const spotifyRoutes = require('./routes/spotify');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false
  }
});

pool.query(`
  CREATE TABLE IF NOT EXISTS "session" (
    "sid" varchar NOT NULL COLLATE "default",
    "sess" json NOT NULL,
    "expire" timestamp(6) NOT NULL,
    CONSTRAINT "session_pkey" PRIMARY KEY ("sid")
  )
`).then(() => {
  console.log("Session table ready");
}).catch(err => {
  console.error("Session table error:", err);
});

const app = express();
app.set('trust proxy', 1);
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: '*' }
});

app.use(cors({
  origin: true,
  credentials: true,
  allowedHeaders: ['Content-Type', 'Cookie', 'Authorization'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));
app.use(express.json());

app.use(session({
  store: new pgSession({
    conString: process.env.DATABASE_URL,
  }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    sameSite: process.env.NODE_ENV === 'production' ? 'none' : 'lax',
    maxAge: 7 * 24 * 60 * 60 * 1000
  }
}));

// Роуты — после session middleware
app.use('/auth', authRoutes);
app.use('/friends', friendsRoutes);
app.use('/sessions', sessionRoutes);
app.use('/spotify', spotifyRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'SyncM server is running' });
});

setupSocket(io);

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});