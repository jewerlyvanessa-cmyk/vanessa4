#!/usr/bin/env node
'use strict';

/**
 * Validasi env sebelum PM2 / node server.js.
 * Layout flat (production): nodeapp/scripts/preflight.js  → nodeapp/server.js
 * Layout repo:              backend/scripts/preflight.js → backend/server.js
 * Jalankan: node scripts/preflight.js [--ping-db]
 */
const path = require('path');
const fs = require('fs');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

function fail(message) {
  console.error(`[preflight] FAIL: ${message}`);
  const err = new Error(message);
  err.isPreflightError = true;
  throw err;
}

function ok(message) {
  console.log(`[preflight] OK: ${message}`);
}

function warn(message) {
  console.warn(`[preflight] WARN: ${message}`);
}

const WEAK_JWT_SECRETS = new Set([
  'change-me',
  'changeme',
  'secret',
  'your-strong-secret-here',
  'password',
]);

function assertProductionJwtSecret(secret) {
  const trimmed = String(secret).trim();
  const lower = trimmed.toLowerCase();
  if (WEAK_JWT_SECRETS.has(lower)) {
    fail(
      'JWT_SECRET masih placeholder/default. Generate: node backend/scripts/generate-jwt-secret.js',
    );
  }
  if (trimmed.length < 32) {
    fail('JWT_SECRET terlalu pendek untuk production (min 32 karakter).');
  }
  if (lower.includes('vanessa_jwt_super_secret')) {
    fail(
      'JWT_SECRET masih memakai nilai yang pernah ter-commit di .env.example. Rotate segera.',
    );
  }
}

function runPreflightSync() {
  const isProduction = process.env.NODE_ENV === 'production';
  const isStrict =
    process.env.STRICT_DB_ENV === 'true' || isProduction;

  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) {
    console.warn(`[preflight] WARN: ${envPath} tidak ditemukan (andalkan env sistem / PM2)`);
  } else {
    ok(`.env ditemukan (${envPath})`);
  }

  if (!process.env.JWT_SECRET || !String(process.env.JWT_SECRET).trim()) {
    fail('JWT_SECRET kosong. Set di .env lalu: pm2 restart vanessa --update-env');
  }
  if (isProduction) {
    assertProductionJwtSecret(process.env.JWT_SECRET);
  }

  if (isProduction && process.env.ALLOW_LEGACY_PLAINTEXT_PASSWORD === 'true') {
    fail(
      'ALLOW_LEGACY_PLAINTEXT_PASSWORD=true tidak boleh dipakai di production. ' +
        'Hapus atau set false di .env.',
    );
  }

  if (isProduction && process.env.TRUST_PROXY !== 'true') {
    warn(
      'TRUST_PROXY belum true — rate limit login mungkin salah IP di belakang nginx. ' +
        'Set TRUST_PROXY=true di .env production.',
    );
  }

  const dbKeys = ['DB_USER', 'DB_HOST', 'DB_NAME', 'DB_PASSWORD', 'DB_PORT'];
  const missingDb = dbKeys.filter((k) => !process.env[k] || !String(process.env[k]).trim());
  if (isStrict && missingDb.length > 0) {
    fail(
      `Database env belum lengkap (${missingDb.join(', ')}). ` +
        'Salin .env.example → .env di server.',
    );
  }

  if (isProduction && process.env.DB_SSL !== 'true') {
    const seen = process.env.DB_SSL == null ? '(tidak ada)' : JSON.stringify(process.env.DB_SSL);
    fail(
      `Production wajib DB_SSL=true. Nilai saat ini: ${seen}. ` +
        'Edit .env di folder nodeapp lalu: pm2 restart vanessa --update-env',
    );
  }

  const port = parseInt(process.env.PORT || '3000', 10);
  if (!Number.isFinite(port) || port <= 0) {
    fail(`PORT tidak valid: ${process.env.PORT}`);
  }
  ok(`PORT=${port}`);

  const criticalModules = [
    '../app.js',
    '../routes/orders_core.js',
    '../routes/workshop_core.js',
    '../routes/login.js',
  ];
  for (const rel of criticalModules) {
    try {
      require(path.join(__dirname, rel));
      ok(`require ${path.basename(rel)}`);
    } catch (err) {
      fail(`Modul gagal dimuat (${rel}): ${err.message}`);
    }
  }
}

async function pingDatabase() {
  let db;
  try {
    db = require('../db');
    await db.query('SELECT 1');
    ok('koneksi database');
  } catch (err) {
    fail(`Database tidak bisa dihubungi: ${err.message}`);
  } finally {
    try {
      await db?.pool?.end?.();
    } catch (_) {
      /* ignore */
    }
  }
}

async function runPreflight({ pingDb = false } = {}) {
  runPreflightSync();
  if (pingDb) {
    await pingDatabase();
  }
  console.log('[preflight] Siap start backend.');
}

module.exports = {
  runPreflightSync,
  runPreflight,
  assertProductionJwtSecret,
  WEAK_JWT_SECRETS,
};

if (require.main === module) {
  const pingDb = process.argv.includes('--ping-db');
  runPreflight({ pingDb })
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err.message || err);
      process.exit(1);
    });
}
