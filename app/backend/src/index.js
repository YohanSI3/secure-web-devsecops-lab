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

// Les 6 règles ci-dessous ("good_helmet_checks") confirment que helmet()
// ajoute bien ces en-têtes -- pas des problèmes, mal classées "Blocking"
// par le pack Semgrep. Voir app/backend/README.md#sast.
// nosemgrep: ajinabraham.njsscan.good.good_helmet_checks.helmet_header_dns_prefetch,ajinabraham.njsscan.good.good_helmet_checks.helmet_header_hsts,ajinabraham.njsscan.good.good_helmet_checks.helmet_header_ienoopen,ajinabraham.njsscan.good.good_helmet_checks.helmet_header_nosniff,ajinabraham.njsscan.good.good_helmet_checks.helmet_header_x_powered_by,ajinabraham.njsscan.good.good_helmet_checks.helmet_header_xss_filter
app.use(helmet());
app.use(express.json());

const PgSession = pgSessionFactory(session);
// `domain` et `expires` volontairement absents : voir
// app/backend/README.md#sast pour pourquoi (portée de cookie la plus
// étroite possible, `maxAge` préféré à `expires`). `path` en revanche
// fixé explicitement ci-dessous suite au même scan.
app.use(
  // nosemgrep: ajinabraham.njsscan.headers.header_cookie.cookie_session_no_domain,javascript.express.security.audit.express-cookie-settings.express-cookie-session-no-domain,javascript.express.security.audit.express-cookie-settings.express-cookie-session-no-expires
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
      path: '/',
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
