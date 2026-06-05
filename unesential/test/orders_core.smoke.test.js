'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { registerOrdersCoreRoutes } = require('../../backend/routes/orders_core');

function makeOrdersApp() {
  const app = express();
  app.use(express.json());
  const db = {
    async query() {
      throw new Error('db.query should not run for validation-only tests');
    },
    async getClient() {
      throw new Error('db.getClient should not run for validation-only tests');
    },
  };
  const upload = {
    single: () => (req, res, next) => next(),
  };
  registerOrdersCoreRoutes(app, {
    db,
    upload,
    notifyClients: () => {},
    getOrdersDaily: (req, res) => res.status(501).json({ error: 'mock' }),
    getWss: () => null,
  });
  return app;
}

test('GET /orders/payment-summary returns 400 without order_id', async () => {
  const res = await request(makeOrdersApp()).get('/orders/payment-summary');
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});

test('GET /store-operational returns 400 without branch_id', async () => {
  const res = await request(makeOrdersApp()).get('/store-operational');
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});

test('POST /orders/pickup returns 400 without order_id or order_number', async () => {
  const app = express();
  app.use(express.json());
  const db = {
    async getClient() {
      return {
        async query() {
          throw new Error('db.query should not run for pickup validation test');
        },
        release() {},
      };
    },
  };
  registerOrdersCoreRoutes(app, {
    db,
    upload: { single: () => (_req, _res, next) => next() },
    notifyClients: () => {},
    getOrdersDaily: (_req, res) => res.status(501).json({ error: 'mock' }),
  });
  const res = await request(app)
    .post('/orders/pickup')
    .send({ branch_id: '1' });
  assert.equal(res.status, 400);
  assert.match(String(res.body?.error ?? ''), /order_id|order_number/i);
});
