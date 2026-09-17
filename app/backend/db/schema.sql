-- Schéma applicatif. La table de session (connect-pg-simple) n'est pas
-- ici : créée automatiquement par le module lui-même (createTableIfMissing),
-- pour rester alignée avec son schéma exact au fil des versions plutôt que
-- de le dupliquer à la main ici.

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    -- Verrouillage de compte après échecs répétés (voir
    -- app/backend/src/routes/auth.js) -- stocké par utilisateur, pas par
    -- IP : protège même si l'attaquant change d'adresse.
    failed_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    -- ON DELETE SET NULL : l'entrée d'audit survit à la suppression du
    -- compte concerné (traçabilité), sans jamais bloquer cette suppression.
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    ip TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id BIGSERIAL PRIMARY KEY,
    -- ON DELETE CASCADE, contrairement à audit_log (SET NULL) : un jeton
    -- de reset n'a aucune valeur de traçabilité en soi une fois le compte
    -- supprimé, rien à préserver.
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Jamais le jeton en clair : seul son hash SHA-256 est stocké (voir
    -- app/backend/src/routes/auth.js) -- une fuite de la base ne permet
    -- pas d'utiliser directement les jetons émis, seulement d'apprendre
    -- qu'une demande a existé.
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);
