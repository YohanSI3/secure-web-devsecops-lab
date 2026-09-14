require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const session = require('express-session');
const pgSessionFactory = require('connect-pg-simple');

const { pool } = require('./db');
const authRoutes = require('./routes/auth');
const adminRoutes = require('./routes/admin');

const app = express();
const port = process.env.PORT || 3000;

if (!process.env.SESSION_SECRET) {
  throw new Error('SESSION_SECRET manquant (voir app/backend/.env.example)');
}

// Nécessaire pour que req.secure / req.ip reflètent la vraie requête
// client plutôt que la connexion locale Nginx -> Node : le TLS se termine
// chez Nginx (voir nginx/snippets/tls-hardening.conf), la connexion
// Nginx -> ce process est en clair sur 127.0.0.1. Sans ceci, le cookie de
// session "secure" ne serait jamais envoyé (Express le croirait servi en
// HTTP) et req.ip renverrait l'IP de Nginx, pas celle du client.
app.set('trust proxy', 1);

app.use(helmet());
app.use(express.json());

const PgSession = pgSessionFactory(session);
app.use(
  session({
    store: new PgSession({ pool, createTableIfMissing: true }),
    name: 'sid',
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      maxAge: 1000 * 60 * 60 * 2, // 2h
    },
  })
);

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'ok', db: 'unreachable' });
  }
});

app.use('/auth', authRoutes);
app.use('/admin', adminRoutes);

// Handler d'erreur générique : jamais renvoyer un message d'erreur ou une
// stack trace au client (fuite d'information sur l'implémentation) --
// seul le log serveur reçoit le détail.
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'internal_error' });
});

// 127.0.0.1 uniquement : le backend ne doit jamais être atteignable
// directement depuis le réseau, seul Nginx (reverse proxy local) doit
// pouvoir lui parler. Voir app/backend/README.md.
app.listen(port, '127.0.0.1', () => {
  console.log(`backend listening on 127.0.0.1:${port}`);
});
