'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { registerOrdersStoreOperationalRoutes } = require('../../backend/routes/orders_store_operational');

function makeApp() {
  const app = express();
  app.use(express.json());
  const db = {
    async query() {
      throw new Error('db.query should not run for store-operational validation test');
    },
  };
  registerOrdersStoreOperationalRoutes(app, { db });
  return app;
}

test('GET /store-operational returns 400 without branch_id', async () => {
  const res = await request(makeApp()).get('/store-operational');
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});

test('POST /store-operational returns 400 without branch_id', async () => {
  const res = await request(makeApp())
    .post('/store-operational')
    .send({ amount: 1000, category: 'listrik' });
  assert.equal(res.status, 400);
});
