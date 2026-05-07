const { Pool } = require('pg');

const requiredDbEnv = ['DB_USER', 'DB_HOST', 'DB_NAME', 'DB_PASSWORD', 'DB_PORT'];
const missingDbEnv = requiredDbEnv.filter((key) => !process.env[key]);
const isStrictDbEnv =
  process.env.STRICT_DB_ENV === 'true' ||
  process.env.NODE_ENV === 'production';

if (isStrictDbEnv && missingDbEnv.length > 0) {
  throw new Error(`Missing required database environment variables: ${missingDbEnv.join(', ')}`);
}

if (!isStrictDbEnv && missingDbEnv.length > 0) {
  // Keep local/dev usable while production remains strict.
  console.warn(
    `[db] Missing env vars (${missingDbEnv.join(', ')}). Falling back to local defaults for development.`
  );
}
if (!isStrictDbEnv && (!process.env.DB_PASSWORD || process.env.DB_PASSWORD === 'password')) {
  console.warn(
    '[db] Using default DB password — set DB_* and STRICT_DB_ENV=true for production-like deployments.'
  );
}

// Konfigurasi koneksi database
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'vanessa3',
  password: process.env.DB_PASSWORD || 'password',
  port: parseInt(process.env.DB_PORT || '5432', 10),
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  getClient: () => pool.connect(),
};
