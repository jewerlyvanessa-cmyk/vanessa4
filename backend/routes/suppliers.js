'use strict';

const express = require('express');
const { ensureSuppliersTable } = require('../lib/suppliers_schema');

function serializeSupplierRow(row) {
  return {
    ...row,
    supplier_id: row.supplier_id?.toString?.() ?? row.supplier_id,
  };
}

function createSuppliersRouter(deps) {
  const { db } = deps;
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      await ensureSuppliersTable(db);
      const status = String(req.query.status ?? '').trim().toLowerCase();
      const q = String(req.query.q ?? '').trim();

      let query = `
        SELECT
          supplier_id,
          name,
          code,
          contact_name,
          phone,
          email,
          address,
          notes,
          status,
          created_at,
          updated_at
        FROM suppliers
        WHERE 1=1
      `;
      const params = [];
      let idx = 1;

      if (status === 'active' || status === 'inactive') {
        query += ` AND status = $${idx}`;
        params.push(status);
        idx++;
      }

      if (q) {
        query += ` AND (
          name ILIKE $${idx}
          OR COALESCE(code, '') ILIKE $${idx}
          OR COALESCE(contact_name, '') ILIKE $${idx}
          OR COALESCE(phone, '') ILIKE $${idx}
          OR COALESCE(email, '') ILIKE $${idx}
        )`;
        params.push(`%${q}%`);
        idx++;
      }

      query += ` ORDER BY LOWER(name) ASC`;

      const result = await db.query(query, params);
      res.status(200).json(result.rows.map(serializeSupplierRow));
    } catch (error) {
      console.error('GET /suppliers:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.get('/:id', async (req, res) => {
    try {
      await ensureSuppliersTable(db);
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id) || id <= 0) {
        return res.status(400).json({ error: 'supplier_id tidak valid' });
      }
      const result = await db.query(
        `
          SELECT *
          FROM suppliers
          WHERE supplier_id = $1
          LIMIT 1
        `,
        [id]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Supplier tidak ditemukan' });
      }
      res.status(200).json(serializeSupplierRow(result.rows[0]));
    } catch (error) {
      console.error('GET /suppliers/:id:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.post('/', async (req, res) => {
    try {
      await ensureSuppliersTable(db);
      const {
        name,
        code,
        contact_name,
        phone,
        email,
        address,
        notes,
        status,
      } = req.body ?? {};

      const nameTrim = String(name ?? '').trim();
      if (!nameTrim) {
        return res.status(400).json({ error: 'name wajib diisi' });
      }

      const statusNorm =
        String(status ?? 'active').trim().toLowerCase() === 'inactive'
          ? 'inactive'
          : 'active';

      const result = await db.query(
        `
          INSERT INTO suppliers (
            name, code, contact_name, phone, email, address, notes, status
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
          RETURNING *
        `,
        [
          nameTrim,
          String(code ?? '').trim() || null,
          String(contact_name ?? '').trim() || null,
          String(phone ?? '').trim() || null,
          String(email ?? '').trim() || null,
          String(address ?? '').trim() || null,
          String(notes ?? '').trim() || null,
          statusNorm,
        ]
      );
      res.status(201).json(serializeSupplierRow(result.rows[0]));
    } catch (error) {
      console.error('POST /suppliers:', error);
      if (error.code === '23505') {
        return res.status(400).json({ error: 'Nama supplier sudah terdaftar' });
      }
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.put('/:id', async (req, res) => {
    try {
      await ensureSuppliersTable(db);
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id) || id <= 0) {
        return res.status(400).json({ error: 'supplier_id tidak valid' });
      }

      const {
        name,
        code,
        contact_name,
        phone,
        email,
        address,
        notes,
        status,
      } = req.body ?? {};

      const nameTrim = String(name ?? '').trim();
      if (!nameTrim) {
        return res.status(400).json({ error: 'name wajib diisi' });
      }

      const statusNorm =
        String(status ?? 'active').trim().toLowerCase() === 'inactive'
          ? 'inactive'
          : 'active';

      const result = await db.query(
        `
          UPDATE suppliers
          SET
            name = $1,
            code = $2,
            contact_name = $3,
            phone = $4,
            email = $5,
            address = $6,
            notes = $7,
            status = $8,
            updated_at = NOW()
          WHERE supplier_id = $9
          RETURNING *
        `,
        [
          nameTrim,
          String(code ?? '').trim() || null,
          String(contact_name ?? '').trim() || null,
          String(phone ?? '').trim() || null,
          String(email ?? '').trim() || null,
          String(address ?? '').trim() || null,
          String(notes ?? '').trim() || null,
          statusNorm,
          id,
        ]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Supplier tidak ditemukan' });
      }
      res.status(200).json(serializeSupplierRow(result.rows[0]));
    } catch (error) {
      console.error('PUT /suppliers/:id:', error);
      if (error.code === '23505') {
        return res.status(400).json({ error: 'Nama supplier sudah terdaftar' });
      }
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  router.delete('/:id', async (req, res) => {
    try {
      await ensureSuppliersTable(db);
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id) || id <= 0) {
        return res.status(400).json({ error: 'supplier_id tidak valid' });
      }
      const result = await db.query(
        `
          UPDATE suppliers
          SET status = 'inactive', updated_at = NOW()
          WHERE supplier_id = $1
          RETURNING *
        `,
        [id]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Supplier tidak ditemukan' });
      }
      res.status(200).json(serializeSupplierRow(result.rows[0]));
    } catch (error) {
      console.error('DELETE /suppliers/:id:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}

function registerSuppliersRoutes(app, deps) {
  const router = createSuppliersRouter(deps);
  app.use('/suppliers', router);
  app.use('/api/suppliers', router);
}

module.exports = { registerSuppliersRoutes, createSuppliersRouter };
