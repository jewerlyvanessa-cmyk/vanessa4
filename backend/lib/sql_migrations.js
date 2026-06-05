'use strict';

const fs = require('fs');
const path = require('path');

/** PostgreSQL / pesan umum: skema sudah ada (DB lama tanpa catatan sql_migrations). */
function isBenignMigrationError(err) {
  const code = err?.code;
  if (code === '42701') return true; // duplicate_column
  if (code === '42P07') return true; // duplicate_table
  if (code === '42710') return true; // duplicate_object (constraint, index, …)
  const msg = String(err?.message ?? '').toLowerCase();
  return msg.includes('already exists');
}

async function ensureSqlMigrationsTable(db) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS sql_migrations (
      filename TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

/**
 * Jalankan file .sql di [migrationsDir] yang belum tercatat di sql_migrations.
 * @returns {Promise<string[]>} nama file yang baru dijalankan
 */
async function runPendingSqlMigrations(db, migrationsDir) {
  const dir = path.resolve(migrationsDir);
  if (!fs.existsSync(dir)) {
    throw new Error(`Migrations directory not found: ${dir}`);
  }

  await ensureSqlMigrationsTable(db);
  const appliedRes = await db.query('SELECT filename FROM sql_migrations ORDER BY filename');
  const appliedSet = new Set(appliedRes.rows.map((r) => r.filename));

  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const ran = [];
  for (const file of files) {
    if (appliedSet.has(file)) continue;

    const fullPath = path.join(dir, file);
    const sql = fs.readFileSync(fullPath, 'utf8');
    if (!sql.trim()) {
      await db.query('INSERT INTO sql_migrations (filename) VALUES ($1)', [file]);
      ran.push(file);
      continue;
    }

    const client = await db.getClient();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO sql_migrations (filename) VALUES ($1)', [file]);
      await client.query('COMMIT');
      ran.push(file);
    } catch (err) {
      await client.query('ROLLBACK');
      if (isBenignMigrationError(err)) {
        console.warn(
          `[migrate:sql] SKIP (schema sudah ada): ${file} — ${err.message}`,
        );
        await db.query(
          'INSERT INTO sql_migrations (filename) VALUES ($1) ON CONFLICT (filename) DO NOTHING',
          [file],
        );
        ran.push(file);
        continue;
      }
      throw new Error(`SQL migration "${file}" failed: ${err.message}`);
    } finally {
      client.release();
    }
  }

  return ran;
}

module.exports = {
  ensureSqlMigrationsTable,
  isBenignMigrationError,
  runPendingSqlMigrations,
};
