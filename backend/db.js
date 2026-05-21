const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const { Pool } = require('pg');
const fs = require('fs');

const requiredDbEnv = ['DB_USER', 'DB_HOST', 'DB_NAME', 'DB_PASSWORD', 'DB_PORT'];
const missingDbEnv = requiredDbEnv.filter((key) => !process.env[key]);
const envPath = path.join(__dirname, '.env');
const envFileExists = fs.existsSync(envPath);

const isStrictDbEnv =
  process.env.STRICT_DB_ENV === 'true' ||
  process.env.NODE_ENV === 'production';

// Jangan paksa env lengkap hanya karena jalan di PM2 — ecosystem sudah set NODE_ENV/STRICT_DB_ENV.
const mustHaveEnv =
  isStrictDbEnv ||
  (missingDbEnv.length > 0 && !envFileExists && process.env.NODE_ENV !== 'development');

if (mustHaveEnv && missingDbEnv.length > 0) {
  throw new Error(
    `Database env tidak lengkap (${missingDbEnv.join(', ')}). ` +
      `Buat file ${envPath} dari .env.example lalu: pm2 restart vanessa --update-env`
  );
}

if (!mustHaveEnv && missingDbEnv.length > 0) {
  console.warn(
    `[db] Missing env vars (${missingDbEnv.join(', ')}). Falling back to local defaults for development.`
  );
}
if (!mustHaveEnv && (!process.env.DB_PASSWORD || process.env.DB_PASSWORD === 'password')) {
  console.warn(
    '[db] Using default DB password — set DB_* in backend/.env for production.'
  );
}

const poolConfig = {
  user: process.env.DB_USER || 'vanessa_store',
  host: process.env.DB_HOST || 'vanessa.id',
  database: process.env.DB_NAME || 'vanessa_store',
  password: process.env.DB_PASSWORD || 'Aza|ia2I{28gQbLk',
  port: parseInt(process.env.DB_PORT || '5432', 10),
};

if (process.env.DB_SSL === 'true') {
  poolConfig.ssl = {
    rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
  };
}

const pool = new Pool(poolConfig);

/** Semua TIMESTAMP tanpa zona (orders.created_at, dll.) = jam dinding WIB. */
const DB_SESSION_TIMEZONE =
  process.env.DB_TIMEZONE || 'Asia/Jakarta';

async function applySessionTimezone(client) {
  await client.query(`SET TIME ZONE '${DB_SESSION_TIMEZONE}'`);
}

pool.on('connect', (client) => {
  applySessionTimezone(client).catch((err) => {
    console.error('[db] SET TIME ZONE failed:', err.message);
  });
});

console.log(
  `[db] Pool: ${poolConfig.user}@${poolConfig.host}:${poolConfig.port}/${poolConfig.database}` +
    ` (session TZ: ${DB_SESSION_TIMEZONE})` +
    (envFileExists ? ' (.env loaded)' : ' (NO .env file — using defaults)')
);

pool.on('error', (err) => {
  console.error('[db] Pool error:', err.message);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  getClient: async () => {
    const client = await pool.connect();
    await applySessionTimezone(client);
    return client;
  },
};
