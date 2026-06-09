const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const { Pool } = require('pg');
const fs = require('fs');

function envFlag(name) {
  const raw = process.env[name];
  if (raw == null) return false;
  const v = String(raw).trim().toLowerCase();
  return v === 'true' || v === '1' || v === 'yes';
}

const requiredDbEnv = ['DB_USER', 'DB_HOST', 'DB_NAME', 'DB_PASSWORD', 'DB_PORT'];
const missingDbEnv = requiredDbEnv.filter((key) => !process.env[key]);
const envPath = path.join(__dirname, '.env');
const envFileExists = fs.existsSync(envPath);

const isProduction = process.env.NODE_ENV === 'production';
const isStrictDbEnv =
  process.env.STRICT_DB_ENV === 'true' || isProduction;
const isLocalDev =
  process.env.NODE_ENV === 'development' && !isStrictDbEnv;

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
    `[db] Missing env vars (${missingDbEnv.join(', ')}). Using localhost dev defaults.`
  );
}

if (isProduction && !envFlag('DB_SSL')) {
  const seen = process.env.DB_SSL == null ? '(tidak ada)' : JSON.stringify(process.env.DB_SSL);
  throw new Error(
    `[db] Production requires DB_SSL=true. Nilai saat ini: ${seen}. ` +
      'Edit .env di folder nodeapp, set DB_SSL=true, lalu: pm2 restart vanessa --update-env'
  );
}

function sslConfigFromEnv() {
  if (!envFlag('DB_SSL')) return undefined;
  return {
    rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
  };
}

/** Semua TIMESTAMP tanpa zona (orders.created_at, dll.) = jam dinding WIB. */
const DB_SESSION_TIMEZONE =
  process.env.DB_TIMEZONE || 'Asia/Jakarta';

const poolConfig = {
  user: process.env.DB_USER || (isLocalDev ? 'postgres' : undefined),
  host: process.env.DB_HOST || (isLocalDev ? 'localhost' : undefined),
  database: process.env.DB_NAME || (isLocalDev ? 'vanessa_store' : undefined),
  password: process.env.DB_PASSWORD || (isLocalDev ? 'password' : undefined),
  port: parseInt(process.env.DB_PORT || '5432', 10),
  options: `-c timezone=${DB_SESSION_TIMEZONE}`,
};

if (
  isStrictDbEnv &&
  (!poolConfig.user ||
    !poolConfig.host ||
    !poolConfig.database ||
    !poolConfig.password)
) {
  throw new Error(
    '[db] DB_USER, DB_HOST, DB_NAME, and DB_PASSWORD are required in production.'
  );
}

if (envFlag('DB_SSL')) {
  poolConfig.ssl = sslConfigFromEnv();
}

const pool = new Pool(poolConfig);

console.log(
  `[db] Pool: ${poolConfig.user}@${poolConfig.host}:${poolConfig.port}/${poolConfig.database}` +
    ` (session TZ: ${DB_SESSION_TIMEZONE})` +
    (envFileExists ? ' (.env loaded)' : ' (NO .env file)')
);

pool.on('error', (err) => {
  console.error('[db] Pool error:', err.message);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  getClient: () => pool.connect(),
};
