// Autorisation : lit uniquement la session déjà établie (voir
// src/routes/auth.js pour comment userId/role y arrivent) -- aucune
// requête DB ici, l'autorisation ne doit pas dépendre d'un aller-retour
// supplémentaire à chaque requête protégée.

function requireAuth(req, res, next) {
  if (!req.session.userId) {
    return res.status(401).json({ error: 'authentication_required' });
  }
  next();
}

function requireRole(role) {
  return (req, res, next) => {
    if (req.session.role !== role) {
      return res.status(403).json({ error: 'forbidden' });
    }
    next();
  };
}

module.exports = { requireAuth, requireRole };
