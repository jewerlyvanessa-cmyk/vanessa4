const path = require('path');

// Load backend/.env for local dev runs.
// In production, you should provide env vars via your process manager instead.
require('dotenv').config({ path: path.join(__dirname, '.env') });

function bool(v) {
  return String(v ?? '').toLowerCase() === 'true';
}

const ssl =
  bool(process.env.DB_SSL) || process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: bool(process.env.DB_SSL_REJECT_UNAUTHORIZED) }
    : false;

module.exports = {
  migrationsTable: 'pgmigrations',
  dir: path.join(__dirname, 'migrations_js'),
  databaseUrl: {
    user: process.env.DB_USER || 'postgres',
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'vanessa3',
    password: process.env.DB_PASSWORD || 'password',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    ssl,
  },
};

