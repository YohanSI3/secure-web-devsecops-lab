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
