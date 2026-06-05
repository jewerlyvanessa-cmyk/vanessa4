'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { createRequestLogger } = require('../../backend/middleware/request_logger');

describe('createRequestLogger', () => {
  it('logs JSON line on response finish when enabled', async () => {
    const lines = [];
    const origLog = console.log;
    console.log = (msg) => lines.push(String(msg));

    try {
      const app = express();
      app.use(createRequestLogger({ enabled: true }));
      app.get('/ping', (_req, res) => res.status(204).end());

      await request(app).get('/ping').expect(204);

      assert.equal(lines.length, 1);
      const entry = JSON.parse(lines[0]);
      assert.equal(entry.method, 'GET');
      assert.equal(entry.path, '/ping');
      assert.equal(entry.status, 204);
      assert.ok(typeof entry.durationMs === 'number');
    } finally {
      console.log = origLog;
    }
  });
});
