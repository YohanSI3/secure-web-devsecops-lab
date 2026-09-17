const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcrypt');
const { pool } = require('../db');
const { logAudit } = require('../audit');
const { sendPasswordResetEmail } = require('../mail');

const router = express.Router();

const BCRYPT_COST = 12;
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;
const MIN_PASSWORD_LENGTH = 10;
const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_TTL_MINUTES = 30;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// SHA-256, pas bcrypt : le jeton de reset est déjà 256 bits d'aléa
// cryptographique (crypto.randomBytes), pas un secret choisi par un
// humain à protéger contre le brute-force -- un hash rapide suffit pour
// vérifier l'intégrité, la lenteur de bcrypt n'apporte rien ici et
// coûterait un calcul inutile à chaque tentative de reset.
function hashResetToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

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

router.post(
  '/forgot-password',
  asyncHandler(async (req, res) => {
    const { email } = req.body || {};
    if (!isValidEmail(email)) {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const result = await pool.query('SELECT id FROM users WHERE email = $1', [
      email.toLowerCase(),
    ]);
    const user = result.rows[0];

    if (user) {
      const rawToken = crypto.randomBytes(RESET_TOKEN_BYTES).toString('hex');
      const expiresAt = new Date(Date.now() + RESET_TOKEN_TTL_MINUTES * 60 * 1000);

      await pool.query(
        'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
        [user.id, hashResetToken(rawToken), expiresAt]
      );

      // Origine reconstruite depuis la requête elle-même, pas une valeur
      // fixe en config : une seule instance Node sert les 3 environnements
      // (dev/staging/prod, voir nginx/README.md#rate-limiting) via des
      // hôtes différents -- `req.get('host')` renvoie déjà le bon, transmis
      // tel quel par Nginx (`proxy_set_header Host $host;`).
      const resetUrl = `${req.protocol}://${req.get('host')}/reset-password.html?token=${rawToken}`;
      await sendPasswordResetEmail(email, resetUrl);
      await logAudit(user.id, 'password_reset_requested', req.ip);
    }

    // Même réponse que l'email existe ou non -- résistance à l'énumération
    // de comptes, même principe qu'à la connexion (voir
    // app/backend/README.md#résistance-à-lénumération-de-comptes).
    res.json({ message: 'if_account_exists_email_sent' });
  })
);

router.post(
  '/reset-password',
  asyncHandler(async (req, res) => {
    const { token, password } = req.body || {};
    if (typeof token !== 'string' || !isValidPassword(password)) {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const result = await pool.query(
      `SELECT id, user_id FROM password_reset_tokens
       WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()`,
      [hashResetToken(token)]
    );
    const resetRow = result.rows[0];

    if (!resetRow) {
      return res.status(400).json({ error: 'invalid_or_expired_token' });
    }

    const passwordHash = await bcrypt.hash(password, BCRYPT_COST);

    await pool.query(
      'UPDATE users SET password_hash = $1, failed_attempts = 0, locked_until = NULL WHERE id = $2',
      [passwordHash, resetRow.user_id]
    );
    await pool.query('UPDATE password_reset_tokens SET used_at = now() WHERE id = $1', [
      resetRow.id,
    ]);

    // Coupe toutes les sessions actives de ce compte : un reset de mot de
    // passe doit invalider l'accès existant (cas d'usage typique : compte
    // compromis, l'attaquant a peut-être déjà une session ouverte).
    // connect-pg-simple stocke la session sous forme JSON dans `sess` --
    // `userId` y est la même valeur que celle écrite dans req.session.userId
    // (login/register), donc une chaîne (voir la note sur la sérialisation
    // BIGINT du driver pg dans app/backend/README.md).
    await pool.query(`DELETE FROM session WHERE sess->>'userId' = $1`, [resetRow.user_id]);

    await logAudit(resetRow.user_id, 'password_reset_completed', req.ip);
    res.status(204).end();
  })
);

module.exports = router;
