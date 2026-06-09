#!/usr/bin/env node
'use strict';

/**
 * Jalankan migrasi SQL terurut dengan tracking sql_migrations.
 *
 * Repo:  backend/scripts/migrate-sql.js  → backend/migrations/
 * Flat:  nodeapp/scripts/migrate-sql.js  → nodeapp/migrations/
 *
 *   node backend/scripts/migrate-sql.js
 *   node scripts/migrate-sql.js
 */
const path = require('path');

const appRoot = path.join(__dirname, '..');

require('dotenv').config({ path: path.join(appRoot, '.env') });

const db = require(path.join(appRoot, 'db'));
const { runPendingSqlMigrations } = require(path.join(appRoot, 'lib/sql_migrations'));

async function main() {
  const migrationsDir = path.join(appRoot, 'migrations');
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
