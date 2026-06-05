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
      throw new Error('db.query should not run for validation-only opname tests');
    },
    async getClient() {
      throw new Error('db.getClient should not run for validation-only opname tests');
    },
  };
  registerItemsRoutes(app, { db });
  return app;
}

describe('POST /items/stock-opname', () => {
  it('returns 401 without authenticated user', async () => {
    const res = await request(makeItemsApp(null))
      .post('/items/stock-opname')
      .send({ branch_id: '1', lines: [{ item_id: 1, counted_quantity: 1 }] });
    assert.equal(res.status, 401);
  });

  it('returns 403 for disallowed role', async () => {
    const res = await request(
      makeItemsApp({ user_id: 1, role: 'kasir', branch_id: '1' }),
    )
      .post('/items/stock-opname')
      .send({ branch_id: '1', lines: [{ item_id: 1, counted_quantity: 1 }] });
    assert.equal(res.status, 403);
    assert.match(String(res.body?.error ?? ''), /tidak diizinkan/i);
  });

  it('returns 400 when lines empty', async () => {
    const res = await request(
      makeItemsApp({ user_id: 1, role: 'superadmin', branch_id: '1' }),
    )
      .post('/items/stock-opname')
      .send({ branch_id: '1', lines: [] });
    assert.equal(res.status, 400);
    assert.match(String(res.body?.error ?? ''), /lines/i);
  });
});

describe('GET /item-conditions', () => {
  it('returns 200 with joined rows', async () => {
    const app = express();
    app.use(express.json());
    const db = {
      async query(sql) {
        assert.match(String(sql), /^[\s\S]*SELECT[\s\S]*FROM item_conditions/i);
        return {
          rows: [
            {
              condition_id: 1,
              item_id: 10,
              order_id: 20,
              kondisi_fisik: 'baik',
              penyesuaian_berat: 0,
              nilai_resale: 100,
              harga_per_gram: 900,
              potongan_kondisi: 0,
              untung_rugi: null,
              nilai_untung_rugi: 0,
              catatan_kondisi: null,
              foto_kondisi: [],
              created_at: new Date(),
              updated_at: new Date(),
              item_name: 'Cincin',
              kode_produk: 'ABC',
              item_weight: 3,
              material: 'emas',
              purity: '22K',
              order_number: 'ORD-1',
              order_type: 'buyback',
              customer_name: 'Budi',
            },
          ],
        };
      },
    };
    registerItemsRoutes(app, { db });
    const res = await request(app).get('/item-conditions').query({ item_id: '10' });
    assert.equal(res.status, 200);
    assert.equal(res.body.length, 1);
    assert.equal(res.body[0].kode_produk, 'ABC');
  });
});
