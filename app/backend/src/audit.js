const { pool } = require('./db');

// Journal des actions sensibles (Phase 5, IAM : "traçabilité"). userId
// peut être null (ex. tentative de connexion avec un email inexistant --
// on trace quand même la tentative, sans pouvoir la rattacher à un compte).
async function logAudit(userId, action, ip) {
  await pool.query(
    'INSERT INTO audit_log (user_id, action, ip) VALUES ($1, $2, $3)',
    [userId, action, ip]
  );
}

module.exports = { logAudit };
