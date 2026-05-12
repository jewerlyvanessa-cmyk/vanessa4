'use strict';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-for-node-test';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');

const { authenticateToken } = require('../middleware/auth');
const { registerLoginRoutes } = require('../routes/login');

const noopLimiter = (_req, _res, next) => next();

function makeDbForUnknownUser() {
  return {
    async query(sql, params = []) {
      const s = String(sql);
      if (s.includes('information_schema.columns') && s.includes("table_name = 'users'")) {
        return { rows: [] };
      }
      if (s.includes('FROM users u')) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  };
}

test('POST /login returns 401 when user not found', async () => {
  const app = express();
  app.use(express.json());
  registerLoginRoutes(app, {
    db: makeDbForUnknownUser(),
    loginLimiter: noopLimiter,
    SECRET_KEY: 'test-secret-login-routes',
    JWT_EXPIRES_IN: '1h',
  });
  const res = await request(app)
    .post('/login')
    .send({ username: 'nobody', password: 'x' });
  assert.equal(res.status, 401);
});

test('POST /api/auth/switch-context returns 401 without Bearer token', async () => {
  const app = express();
  app.use(express.json());
  const SECRET_KEY = 'test-secret-login-routes-2';
  app.use('/api', authenticateToken(SECRET_KEY));
  registerLoginRoutes(app, {
    db: { query: async () => ({ rows: [] }) },
    loginLimiter: noopLimiter,
    SECRET_KEY,
    JWT_EXPIRES_IN: '1h',
  });
  const res = await request(app)
    .post('/api/auth/switch-context')
    .send({ branch_id: 1, role: 'kasir' });
  assert.equal(res.status, 401);
});

test('POST /api/auth/switch-context returns 400 when body incomplete (with JWT)', async () => {
  const app = express();
  app.use(express.json());
  const SECRET_KEY = 'test-secret-login-routes-3';
  app.use('/api', authenticateToken(SECRET_KEY));
  registerLoginRoutes(app, {
    db: { query: async () => ({ rows: [] }) },
    loginLimiter: noopLimiter,
    SECRET_KEY,
    JWT_EXPIRES_IN: '1h',
  });
  const token = jwt.sign(
    { user_id: 1, username: 'u', role: 'kasir', branch_id: '1' },
    SECRET_KEY
  );
  const res = await request(app)
    .post('/api/auth/switch-context')
    .set('Authorization', `Bearer ${token}`)
    .send({});
  assert.equal(res.status, 400);
});
