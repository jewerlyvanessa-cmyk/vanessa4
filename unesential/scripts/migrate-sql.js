#!/usr/bin/env node
'use strict';

/**
 * Jalankan migrasi SQL terurut dari backend/migrations/ dengan tracking sql_migrations.
 * Usage: npm run migrate:sql
 */
const path = require('path');

require('dotenv').config({
  path: path.join(__dirname, '../../backend/.env'),
});

const db = require('../../backend/db');
const { runPendingSqlMigrations } = require('../../backend/lib/sql_migrations');

async function main() {
  const migrationsDir = path.join(__dirname, '../../backend/migrations');
  console.log(`[migrate:sql] Scanning ${migrationsDir}`);
  const ran = await runPendingSqlMigrations(db, migrationsDir);
  if (ran.length === 0) {
    console.log('[migrate:sql] Nothing to apply — database is up to date.');
  } else {
    console.log(`[migrate:sql] Applied ${ran.length} migration(s):`);
    for (const f of ran) {
      console.log(`  - ${f}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('[migrate:sql] FAILED:', err.message);
    process.exit(1);
  });
