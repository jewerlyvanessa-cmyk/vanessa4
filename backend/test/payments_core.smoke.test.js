'use strict';

/**
 * Smoke: POST /payments tanpa field wajib → 400 sebelum query order.
 */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { registerPaymentsCoreRoutes } = require('../routes/payments_core');

function makeApp() {
  const app = express();
  app.use(express.json());
  const db = {
    async getClient() {
      return {
        async query() {
          throw new Error('db.query should not run for invalid payment body');
        },
        release() {},
      };
    },
  };
  registerPaymentsCoreRoutes(app, { db, notifyClients: () => {} });
  return app;
}

test('POST /payments returns 400 when body is empty', async () => {
  const res = await request(makeApp()).post('/payments').send({});
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});

test('POST /payments returns 400 when order_id missing', async () => {
  const res = await request(makeApp())
    .post('/payments')
    .send({ amount: 1000, method: 'cash' });
  assert.equal(res.status, 400);
});
