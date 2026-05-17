'use strict';

/**
 * Smoke test: app middleware sets Permissions-Policy so Flutter web / QR can use camera on same origin.
 * Does not start server.js (no DB, no listen).
 */
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-for-node-test';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { app } = require('../../backend/app');

test('Permissions-Policy allows camera for same origin', async () => {
  const res = await request(app).get('/__no_such_route_for_header_check__');
  assert.equal(res.status, 404);
  const policy = res.headers['permissions-policy'];
  assert.ok(policy, 'expected Permissions-Policy header');
  assert.match(policy, /camera=\(self\)/);
});
