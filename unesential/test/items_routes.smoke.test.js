'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const { registerItemsRoutes } = require('../../backend/routes/items');

function makeItemsApp(user) {
  const app = express();
  app.use(express.json());
  if (user) {
    app.use((req, _res, next) => {
      req.user = user;
      next();
    });
  }
  const db = {
    async query() {
      throw new Error('db.query should not run for validation-only item tests');
    },
    async getClient() {
      throw new Error('db.getClient should not run for validation-only item tests');
    },
  };
  registerItemsRoutes(app, { db });
  return app;
}

describe('PUT /items/:id', () => {
  it('returns 400 for invalid item id', async () => {
    const res = await request(
      makeItemsApp({ user_id: 1, role: 'admin_toko', branch_id: '1' }),
    )
      .put('/items/0')
      .send({
        branch_id: 1,
        name: 'Test',
        item_code: 'X1',
        status: 'ready',
        weight: 1,
        material: 'EMAS',
        purity: '24K',
      });
    assert.equal(res.status, 400);
  });

  it('returns 400 when required fields missing', async () => {
    const res = await request(
      makeItemsApp({ user_id: 1, role: 'admin_toko', branch_id: '1' }),
    )
      .put('/items/10')
      .send({ branch_id: 1, name: 'Test' });
    assert.equal(res.status, 400);
    assert.match(String(res.body?.error ?? ''), /wajib/i);
  });
});

describe('POST /items/:id/restock', () => {
  it('returns 400 when delta_quantity missing or invalid', async () => {
    const res = await request(
      makeItemsApp({ user_id: 1, role: 'stockist', branch_id: '1' }),
    )
      .post('/items/5/restock')
      .send({ delta_quantity: 0 });
    assert.equal(res.status, 400);
    assert.match(String(res.body?.error ?? ''), /delta_quantity/i);
  });
});
