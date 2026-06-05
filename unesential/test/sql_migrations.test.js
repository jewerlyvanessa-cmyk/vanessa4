'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { runPendingSqlMigrations } = require('../../backend/lib/sql_migrations');

describe('runPendingSqlMigrations', () => {
  it('applies new sql files once and skips on second run', async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vanessa-sql-mig-'));
    fs.writeFileSync(
      path.join(tmpDir, '20260101_test.sql'),
      'SELECT 1 AS ok;',
      'utf8',
    );

    const applied = new Set();
    const db = {
      async query(sql, params) {
        const s = String(sql);
        if (s.includes('CREATE TABLE IF NOT EXISTS sql_migrations')) {
          return { rows: [] };
        }
        if (s.includes('SELECT filename FROM sql_migrations')) {
          return { rows: [...applied].map((filename) => ({ filename })) };
        }
        if (s.includes('INSERT INTO sql_migrations')) {
          applied.add(params[0]);
          return { rows: [] };
        }
        return { rows: [] };
      },
      async getClient() {
        return {
          async query(sql, params) {
            const s = String(sql);
            if (s === 'BEGIN' || s === 'COMMIT' || s === 'ROLLBACK') {
              return { rows: [] };
            }
            if (s.includes('INSERT INTO sql_migrations')) {
              applied.add(params[0]);
              return { rows: [] };
            }
            return { rows: [] };
          },
          release() {},
        };
      },
    };

    const first = await runPendingSqlMigrations(db, tmpDir);
    assert.deepEqual(first, ['20260101_test.sql']);

    const second = await runPendingSqlMigrations(db, tmpDir);
    assert.deepEqual(second, []);

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('marks migration applied when schema already exists (duplicate column)', async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'vanessa-sql-mig-'));
    fs.writeFileSync(
      path.join(tmpDir, '20260101_dup.sql'),
      'ALTER TABLE orders ADD COLUMN customer_id INTEGER;',
      'utf8',
    );

    const applied = new Set();
    const db = {
      async query(sql, params) {
        const s = String(sql);
        if (s.includes('CREATE TABLE IF NOT EXISTS sql_migrations')) {
          return { rows: [] };
        }
        if (s.includes('SELECT filename FROM sql_migrations')) {
          return { rows: [...applied].map((filename) => ({ filename })) };
        }
        if (s.includes('INSERT INTO sql_migrations')) {
          applied.add(params[0]);
          return { rows: [] };
        }
        return { rows: [] };
      },
      async getClient() {
        return {
          async query(sql) {
            const s = String(sql);
            if (s === 'BEGIN' || s === 'COMMIT' || s === 'ROLLBACK') {
              return { rows: [] };
            }
            const err = new Error('column "customer_id" of relation "orders" already exists');
            err.code = '42701';
            throw err;
          },
          release() {},
        };
      },
    };

    const ran = await runPendingSqlMigrations(db, tmpDir);
    assert.deepEqual(ran, ['20260101_dup.sql']);
    assert.ok(applied.has('20260101_dup.sql'));

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });
});
