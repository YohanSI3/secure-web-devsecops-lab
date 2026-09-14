const express = require('express');
const bcrypt = require('bcrypt');
const { pool } = require('../db');
const { logAudit } = require('../audit');

const router = express.Router();

const BCRYPT_COST = 12;
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;
const MIN_PASSWORD_LENGTH = 10;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidEmail(email) {
  return typeof email === 'string' && email.length <= 254 && EMAIL_RE.test(email);
}

// Longueur minimale seule, pas de règle de composition (majuscule/chiffre/
// symbole obligatoires) : les recommandations actuelles (NIST SP 800-63B)
// privilégient la longueur à la complexité imposée, qui pousse surtout
// vers des mots de passe prévisibles ("Password1!"). Détail dans
// Notes/iam/mots-de-passe.md.
function isValidPassword(password) {
  return (
    typeof password === 'string' &&
    password.length >= MIN_PASSWORD_LENGTH &&
    password.length <= 512
  );
}

function asyncHandler(fn) {
  return (req, res, next) => fn(req, res, next).catch(next);
}

async function regenerateSession(req) {
  await new Promise((resolve, reject) => {
    req.session.regenerate((err) => (err ? reject(err) : resolve()));
  });
}

router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const { email, password } = req.body || {};

    if (!isValidEmail(email) || !isValidPassword(password)) {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const passwordHash = await bcrypt.hash(password, BCRYPT_COST);

    let user;
    try {
      const result = await pool.query(
        'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, role',
        [email.toLowerCase(), passwordHash]
      );
      user = result.rows[0];
    } catch (err) {
      if (err.code === '23505') {
        // Violation de la contrainte UNIQUE(email) -- message volontairement
        // générique : voir "Résistance à l'énumération" dans
        // app/backend/README.md.
        return res.status(409).json({ error: 'email_already_registered' });
      }
      throw err;
    }

    // Connecte automatiquement après inscription : identification et
    // authentification se produisent dans le même geste ici.
    await regenerateSession(req);
    req.session.userId = user.id;
    req.session.role = user.role;

    await logAudit(user.id, 'register', req.ip);
    res.status(201).json({ id: user.id, email: user.email, role: user.role });
  })
);

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const { email, password } = req.body || {};
    if (!isValidEmail(email) || typeof password !== 'string') {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const result = await pool.query(
      'SELECT id, email, password_hash, role, failed_attempts, locked_until FROM users WHERE email = $1',
      [email.toLowerCase()]
    );
    const user = result.rows[0];

    if (!user) {
      // Coût bcrypt équivalent à une vraie comparaison, résultat jeté :
      // évite qu'un temps de réponse plus court ne révèle qu'un email
      // n'existe pas (résistance à l'énumération de comptes par timing).
      await bcrypt.hash(password, BCRYPT_COST);
      await logAudit(null, 'login_failed_unknown_email', req.ip);
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      // Même message générique qu'un mot de passe faux : ne pas confirmer
      // l'existence du compte ni son état de verrouillage à l'appelant.
      await logAudit(user.id, 'login_failed_locked', req.ip);
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const passwordMatches = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatches) {
      const attempts = user.failed_attempts + 1;
      const lockedUntil =
        attempts >= MAX_FAILED_ATTEMPTS
          ? new Date(Date.now() + LOCKOUT_MINUTES * 60 * 1000)
          : null;
      await pool.query('UPDATE users SET failed_attempts = $1, locked_until = $2 WHERE id = $3', [
        attempts,
        lockedUntil,
        user.id,
      ]);
      await logAudit(
        user.id,
        lockedUntil ? 'login_failed_now_locked' : 'login_failed',
        req.ip
      );
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    await pool.query('UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = $1', [
      user.id,
    ]);

    // Régénère l'identifiant de session après authentification : protection
    // contre la fixation de session (un ID de session pré-authentification
    // ne doit jamais devenir valide post-authentification).
    await regenerateSession(req);
    req.session.userId = user.id;
    req.session.role = user.role;

    await logAudit(user.id, 'login_success', req.ip);
    res.json({ id: user.id, email: user.email, role: user.role });
  })
);

router.post(
  '/logout',
  asyncHandler(async (req, res) => {
    const userId = req.session.userId || null;
    await new Promise((resolve, reject) => {
      req.session.destroy((err) => (err ? reject(err) : resolve()));
    });
    res.clearCookie('sid');
    await logAudit(userId, 'logout', req.ip);
    res.status(204).end();
  })
);

router.get('/me', (req, res) => {
  if (!req.session.userId) {
    return res.status(401).json({ error: 'authentication_required' });
  }
  res.json({ id: req.session.userId, role: req.session.role });
});

module.exports = router;
