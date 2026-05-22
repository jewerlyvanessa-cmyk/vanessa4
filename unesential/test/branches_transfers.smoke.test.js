'use strict';

/**
 * Smoke: filter branch_type / branch_type_scope pada GET cabang & transfer.
 */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { handleBranchesListGet } = require('../../backend/lib/branches_list_handler');
const { registerTransfersRoutes } = require('../../backend/routes/transfers');

function makeBranchesApp(rows) {
  const app = express();
  const calls = [];
  const db = {
    async query(sql, params) {
      calls.push({ sql: String(sql), params });
      if (String(sql).includes('ALTER TABLE branches')) {
        return { rows: [] };
      }
      if (String(sql).includes('information_schema')) {
        return { rows: [{ '?column?': 1 }] };
      }
      if (String(sql).includes('FROM branches')) {
        return { rows };
      }
      return { rows: [] };
    },
  };
  app.get('/branches', (req, res) => handleBranchesListGet(req, res, db));
  return { app, calls };
}

function makeTransfersApp() {
  const app = express();
  app.use(express.json());
  const transferRows = [
    {
      transfer_id: 1,
      from_branch_id: '10',
      to_branch_id: '11',
      item_name: 'Cincin',
      quantity: 1,
      source_type: 'stok',
      courier: 'A',
      notes: 'antar toko',
      order_id: null,
      created_by: '1',
      approved_by: null,
      status: 'pending',
      created_at: new Date(),
      updated_at: new Date(),
      from_branch_name: 'Toko A',
      to_branch_name: 'Toko B',
      created_by_name: 'u',
      approved_by_name: null,
    },
    {
      transfer_id: 2,
      from_branch_id: '20',
      to_branch_id: '21',
      item_name: 'Gelang',
      quantity: 1,
      source_type: 'stok',
      courier: 'B',
      notes: '[PERMINTAAN_STOK] minta',
      order_id: null,
      created_by: '1',
      approved_by: null,
      status: 'pending',
      created_at: new Date(),
      updated_at: new Date(),
      from_branch_name: 'Toko C',
      to_branch_name: 'Gudang',
      created_by_name: 'u',
      approved_by_name: null,
    },
  ];
  const db = {
    async query(sql, params) {
      const s = String(sql);
      if (s.includes('information_schema')) {
        const col = params && params[0];
        if (col === 'source_type' || col === 'courier') {
          return { rows: [{ '?column?': 1 }] };
        }
        return { rows: [] };
      }
      if (s.includes('FROM transfers')) {
        const scopeIdx = params && params.findIndex((p) => p === 'toko');
        const hasStockExclude = s.includes('NOT ILIKE');
        assert.ok(scopeIdx >= 0 || !s.includes('branch_type'), 'scope filter when requested');
        if (hasStockExclude && params.includes('toko')) {
          return { rows: transferRows.filter((r) => !String(r.notes).includes('[PERMINTAAN_STOK]')) };
        }
        return { rows: transferRows };
      }
      return { rows: [] };
    },
  };
  registerTransfersRoutes(app, { db });
  return app;
}

test('GET /branches?branch_type=toko adds WHERE branch_type', async () => {
  const { app, calls } = makeBranchesApp([
    {
      branch_id: 1,
      name: 'Toko Satu',
      code: 'T1',
      alias: null,
      initials: null,
      address: null,
      phone_number: null,
      status: 'active',
      branch_type: 'toko',
      logo_url: null,
    },
  ]);
  const res = await request(app).get('/branches').query({ branch_type: 'toko' });
  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].branch_type, 'toko');
  const branchQuery = calls.find((c) => c.sql.includes('FROM branches'));
  assert.ok(branchQuery);
  assert.match(branchQuery.sql, /branch_type = \$1/);
  assert.deepEqual(branchQuery.params, ['toko']);
});

test('GET /transfers?branch_type_scope=toko excludes permintaan stok', async () => {
  const app = makeTransfersApp();
  const res = await request(app)
    .get('/transfers')
    .query({ branch_id: '10', branch_type_scope: 'toko' });
  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.ok(!String(res.body[0].notes).includes('[PERMINTAAN_STOK]'));
});

test('POST /transfers returns 400 when required fields missing', async () => {
  const app = makeTransfersApp();
  const res = await request(app).post('/transfers').send({});
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});
