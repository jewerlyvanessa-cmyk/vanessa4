'use strict';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-for-node-test';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const express = require('express');

const { createHealthRouter } = require('../../backend/routes/health');

function makeApp(db) {
  const app = express();
  app.use(createHealthRouter({ db, getWss: () => null }));
  return app;
}

test('GET /health/live returns ok', async () => {
  const db = { query: async () => ({ rows: [] }) };
  const res = await request(makeApp(db)).get('/health/live');
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'ok');
  assert.ok(res.body.timestamp);
});

test('GET /health returns healthy when DB ok', async () => {
  const db = { query: async () => ({ rows: [{ '?column?': 1 }] }) };
  const res = await request(makeApp(db)).get('/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'healthy');
  assert.equal(res.body.services.database, 'connected');
  assert.equal(res.body.services.websocket, 'not initialized');
});

test('GET /health returns 500 when DB fails', async () => {
  const db = {
    query: async () => {
      throw new Error('connection refused');
    },
  };
  const res = await request(makeApp(db)).get('/health');
  assert.equal(res.status, 500);
  assert.equal(res.body.status, 'unhealthy');
});
