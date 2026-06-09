'use strict';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-for-node-test';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');

const { authenticateToken, requireRoles } = require('../../backend/middleware/auth');
const { registerImportDataRoutes } = require('../../backend/routes/import_data');

const SECRET_KEY = 'import-smoke-secret';

function makeImportApp() {
  const app = express();
  const authRequired = authenticateToken(SECRET_KEY);
  registerImportDataRoutes(app, {
    db: { query: async () => ({ rows: [] }) },
    authRequired,
    requireRoles,
  });
  return app;
}

test('POST /api/import/:type returns 401 without JWT', async () => {
  const res = await request(makeImportApp()).post('/api/import/customers');
  assert.equal(res.status, 401);
});

test('POST /api/import/:type returns 403 for non-superadmin', async () => {
  const token = jwt.sign(
    { user_id: 1, username: 'kasir', role: 'kasir', branch_id: '1' },
    SECRET_KEY,
  );
  const res = await request(makeImportApp())
    .post('/api/import/customers')
    .set('Authorization', `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test('POST /api/import/:type returns 400 for unknown dataType', async () => {
  const token = jwt.sign(
    { user_id: 1, username: 'super', role: 'superadmin', branch_id: '1' },
    SECRET_KEY,
  );
  const res = await request(makeImportApp())
    .post('/api/import/not_a_type')
    .set('Authorization', `Bearer ${token}`);
  assert.equal(res.status, 400);
  assert.equal(res.body?.success, false);
});
