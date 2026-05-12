'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { requireLoginBody } = require('../middleware/require_login_body');

test('requireLoginBody returns 400 when username/password missing', async () => {
  const app = express();
  app.use(express.json());
  app.post('/login', requireLoginBody, (_req, res) => res.json({ ok: true }));

  const res = await request(app).post('/login').send({});
  assert.equal(res.status, 400);
  assert.equal(res.body?.error, 'username and password are required');
});

test('requireLoginBody passes when username and password present', async () => {
  const app = express();
  app.use(express.json());
  app.post('/login', requireLoginBody, (_req, res) => res.json({ ok: true }));

  const res = await request(app)
    .post('/login')
    .send({ username: 'u', password: 'p' });
  assert.equal(res.status, 200);
  assert.equal(res.body?.ok, true);
});
