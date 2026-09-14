const { Pool } = require('pg');

// Pool partagé par toute l'application (session store compris) -- une
// seule source de connexions à la base plutôt qu'un Pool par fichier.
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

module.exports = { pool };
