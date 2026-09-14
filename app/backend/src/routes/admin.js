const express = require('express');
const { requireAuth, requireRole } = require('../middleware/auth');

const router = express.Router();

// Route de démonstration RBAC : accessible uniquement à un utilisateur
// authentifié ET de rôle "admin". Voir app/backend/README.md#rbac.
router.get('/ping', requireAuth, requireRole('admin'), (req, res) => {
  res.json({ pong: true, role: req.session.role });
});

module.exports = router;
