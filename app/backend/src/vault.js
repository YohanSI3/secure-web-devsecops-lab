// Client Vault minimal (appels HTTP directs, aucune dépendance npm
// supplémentaire -- `fetch` natif à partir de Node 18, voir
// app/backend/README.md#vault) : connexion AppRole, lecture du secret KV
// (SESSION_SECRET) et des identifiants PostgreSQL dynamiques, puis
// renouvellement périodique du jeton et du bail PostgreSQL pendant toute
// la durée de vie du process. Voir vault/README.md pour la configuration
// côté Vault (policy, rôle AppRole, secrets engines).
const VAULT_ADDR = process.env.VAULT_ADDR;
const VAULT_ROLE_ID = process.env.VAULT_ROLE_ID;
const VAULT_SECRET_ID = process.env.VAULT_SECRET_ID;

if (!VAULT_ADDR || !VAULT_ROLE_ID || !VAULT_SECRET_ID) {
  throw new Error(
    'VAULT_ADDR/VAULT_ROLE_ID/VAULT_SECRET_ID manquants (voir app/backend/.env.example et vault/README.md)'
  );
}

const APP_DB = 'secure_web_lab';
const DB_ROLE_PATH = 'database/creds/secure-web-lab-app';
const KV_PATH = 'secret/data/secure-web-lab/backend';

let clientToken = null;
let tokenRenewable = false;
let dbLeaseId = null;

async function vaultRequest(method, path, { token, body } = {}) {
  const res = await fetch(`${VAULT_ADDR}/v1/${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { 'X-Vault-Token': token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Vault ${method} ${path} -> ${res.status}: ${text}`);
  }
  return res.json();
}

// Renouvelle à mi-vie du bail plutôt qu'à la toute fin -- marge pour
// absorber un échec transitoire (Vault temporairement inatteignable) et
// retenter avant l'expiration réelle. Jamais plus tôt que 30s, pour ne
// pas marteler Vault si un TTL très court était un jour configuré.
function scheduleRenewal(leaseDurationSeconds, renewFn) {
  const delayMs = Math.max((leaseDurationSeconds * 1000) / 2, 30_000);
  setTimeout(renewFn, delayMs);
}

async function login() {
  const data = await vaultRequest('POST', 'auth/approle/login', {
    body: { role_id: VAULT_ROLE_ID, secret_id: VAULT_SECRET_ID },
  });
  clientToken = data.auth.client_token;
  tokenRenewable = data.auth.renewable;
  scheduleRenewal(data.auth.lease_duration, renewToken);
  return clientToken;
}

async function renewToken() {
  try {
    if (!tokenRenewable) {
      throw new Error('jeton non renouvelable');
    }
    const data = await vaultRequest('POST', 'auth/token/renew-self', { token: clientToken });
    scheduleRenewal(data.auth.lease_duration, renewToken);
  } catch (err) {
    // Le jeton Vault lui-même n'a aucune incidence sur une connexion
    // PostgreSQL déjà ouverte -- une reconnexion AppRole silencieuse ici
    // est sans risque, contrairement à l'échec de renouvellement du bail
    // PostgreSQL plus bas.
    console.error('Renouvellement du jeton Vault impossible, nouvelle connexion AppRole :', err.message);
    await login();
  }
}

async function fetchSessionSecret() {
  const data = await vaultRequest('GET', KV_PATH, { token: clientToken });
  return data.data.data.SESSION_SECRET;
}

async function fetchDatabaseUrl() {
  const data = await vaultRequest('GET', DB_ROLE_PATH, { token: clientToken });
  dbLeaseId = data.lease_id;
  scheduleRenewal(data.lease_duration, renewDbLease);
  const { username, password } = data.data;
  // encodeURIComponent systématique sur le mot de passe : déjà appris à
  // la dure sur le mot de passe statique du rôle applicatif (voir
  // app/backend/README.md, le '/' d'un mot de passe base64 qui cassait le
  // parsing d'URI) -- s'applique tout autant à un mot de passe généré par
  // Vault, dont le jeu de caractères exact n'est pas garanti par ce code.
  return `postgresql://${username}:${encodeURIComponent(password)}@127.0.0.1:5432/${APP_DB}`;
}

async function renewDbLease() {
  try {
    const data = await vaultRequest('PUT', 'sys/leases/renew', {
      token: clientToken,
      body: { lease_id: dbLeaseId },
    });
    scheduleRenewal(data.lease_duration, renewDbLease);
  } catch (err) {
    // Contrairement au jeton Vault, le pool `pg` existant (voir
    // app/backend/src/db.js) a été créé une seule fois avec cet
    // identifiant précis -- pas de hot-swap du pool en cours de vie du
    // process dans ce lab (voir app/backend/README.md#vault pour pourquoi
    // et ce qu'il faudrait pour le faire proprement). Échec visible et
    // arrêt du process plutôt que de continuer avec un identifiant
    // bientôt révoqué par PostgreSQL lui-même.
    console.error('Renouvellement du bail PostgreSQL dynamique impossible :', err.message);
    process.exit(1);
  }
}

async function loadSecrets() {
  await login();
  const [sessionSecret, databaseUrl] = await Promise.all([fetchSessionSecret(), fetchDatabaseUrl()]);
  return { sessionSecret, databaseUrl };
}

module.exports = { loadSecrets };
