'use strict';

/**
 * Smoke: GET /orders/daily
 * - tanpa branch_id → 400 sebelum query DB;
 * - ada branch_id tanpa JWT user → 403 (scope cabang).
 */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const getOrdersDaily = require('../../backend/routes/orders_daily_handler');

test('GET /orders/daily returns 400 when branch_id is missing', async () => {
  const app = express();
  app.get('/orders/daily', getOrdersDaily);
  const res = await request(app).get('/orders/daily');
  assert.equal(res.status, 400);
  assert.ok(res.body?.error);
});

test('GET /orders/daily returns 403 when branch_id present but no JWT user', async () => {
  const app = express();
  app.get('/orders/daily', getOrdersDaily);
  const res = await request(app).get('/orders/daily').query({ branch_id: '1' });
  assert.equal(res.status, 403);
  assert.ok(res.body?.error);
});
