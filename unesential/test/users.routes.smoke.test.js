'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { registerUsersRoutes } = require('../../backend/routes/users');

test('POST /users returns 400 without username/password', async () => {
  const app = express();
  app.use(express.json());
  registerUsersRoutes(app, {
    db: {
      async query() {
        throw new Error('db should not be called');
      },
    },
  });
  const res = await request(app).post('/users').send({ role: 'kasir' });
  assert.equal(res.status, 400);
  assert.match(String(res.body?.error || ''), /username/i);
});

test('GET /users returns grouped users from mock db', async () => {
  const app = express();
  app.use(express.json());
  registerUsersRoutes(app, {
    db: {
      async query() {
        return {
          rows: [
            {
              user_id: 1,
              username: 'alice',
              status: 'active',
              created_at: '2026-01-01',
              updated_at: '2026-01-01',
              role: 'kasir',
              branch_id: 2,
              branch_name: 'Toko A',
            },
          ],
        };
      },
    },
  });
  const res = await request(app).get('/users');
  assert.equal(res.status, 200);
  assert.ok(Array.isArray(res.body));
  assert.equal(res.body[0].username, 'alice');
  assert.equal(res.body[0].branches.length, 1);
});
