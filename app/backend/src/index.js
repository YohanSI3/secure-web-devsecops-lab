require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

app.use(helmet());
app.use(express.json());

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'ok', db: 'unreachable' });
  }
});

// 127.0.0.1 uniquement : le backend ne doit jamais être atteignable
// directement depuis le réseau, seul Nginx (reverse proxy local) doit
// pouvoir lui parler. Voir app/backend/README.md.
app.listen(port, '127.0.0.1', () => {
  console.log(`backend listening on 127.0.0.1:${port}`);
});
