'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { writeAuditLog } = require('../../backend/lib/audit_log');

describe('writeAuditLog', () => {
  it('inserts audit row with parsed user and branch ids', async () => {
    const inserts = [];
    const db = {
      async query(sql, params) {
        const s = String(sql);
        if (s.includes('CREATE TABLE IF NOT EXISTS audit_log')) {
          return { rows: [] };
        }
        if (s.includes('CREATE INDEX IF NOT EXISTS idx_audit_log')) {
          return { rows: [] };
        }
        if (s.includes('INSERT INTO audit_log')) {
          inserts.push({ sql: s, params });
          return { rows: [] };
        }
        throw new Error(`unexpected query: ${s}`);
      },
    };

    const req = {
      user: { user_id: 42, branch_id: 7 },
      headers: { 'x-forwarded-for': '203.0.113.1, 10.0.0.1' },
      socket: { remoteAddress: '127.0.0.1' },
    };

    await writeAuditLog(db, req, {
      action: 'payment.create',
      entityType: 'payment',
      entityId: 'pay-99',
      branchId: 7,
      payload: { amount: 150000 },
    });

    assert.equal(inserts.length, 1);
    const { params } = inserts[0];
    assert.equal(params[0], 42);
    assert.equal(params[1], 7);
    assert.equal(params[2], 'payment.create');
    assert.equal(params[3], 'payment');
    assert.equal(params[4], 'pay-99');
    assert.deepEqual(JSON.parse(params[5]), { amount: 150000 });
    assert.equal(params[6], '203.0.113.1');
  });

  it('skips insert when table setup fails', async () => {
    const db = {
      async query() {
        throw new Error('db down');
      },
    };

    await assert.doesNotReject(() =>
      writeAuditLog(db, {}, { action: 'x', entityType: 'y' }),
    );
  });
});
