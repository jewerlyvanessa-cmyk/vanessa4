const express = require('express');
const router = express.Router();
const db = require('../db');

let _cachedPaymentsProofUrlColumnExists = null;
async function paymentsHasProofUrlColumn() {
  if (_cachedPaymentsProofUrlColumnExists !== null) {
    return _cachedPaymentsProofUrlColumnExists;
  }
  try {
    const result = await db.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'proof_url'
        LIMIT 1
      `,
    );
    _cachedPaymentsProofUrlColumnExists = result.rowCount > 0;
  } catch (_) {
    _cachedPaymentsProofUrlColumnExists = false;
  }
  return _cachedPaymentsProofUrlColumnExists;
}

const _cachedCustomersColumnExists = new Map();
async function customersHasColumn(columnName) {
  if (_cachedCustomersColumnExists.has(columnName)) {
    return _cachedCustomersColumnExists.get(columnName);
  }
  let exists = false;
  try {
    const result = await db.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'customers'
          AND column_name = $1
        LIMIT 1
      `,
      [columnName],
    );
    exists = result.rowCount > 0;
  } catch (_) {
    exists = false;
  }
  _cachedCustomersColumnExists.set(columnName, exists);
  return exists;
}

// Endpoint: GET /api/customers
router.get('/customers', async (req, res) => {
  try {
    // Untuk sementara, dapatkan branch_id dari query param (nanti dari auth)
    const branchId = req.query.branch_id;
    let query = 'SELECT * FROM customers';
    let values = [];

    if (branchId) {
      query += ' WHERE branch_id = $1 OR branch_id IS NULL';
      values = [branchId];
    }

    const result = await db.query(query, values);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// Endpoint: GET /api/customers/:id/transactions
// Riwayat transaksi per pelanggan (order + pembayaran terakhir jika ada)
router.get('/customers/:id/transactions', async (req, res) => {
  try {
    const { id } = req.params;
    const { branch_id, limit, offset } = req.query;

    const lim = Math.max(1, Math.min(parseInt(limit || '50', 10) || 50, 200));
    const off = Math.max(0, parseInt(offset || '0', 10) || 0);

    const hasProofUrl = await paymentsHasProofUrlColumn();
    const proofUrlSelect = hasProofUrl ? 'p.proof_url' : 'NULL';

    let query = `
      SELECT
        o.order_id,
        o.created_at,
        o.order_type,
        o.status AS order_status,
        o.jumlah,
        o.total,
        o.diskon,
        o.branch_id,
        b.name AS branch_name,
        p.payment_id,
        p.status AS payment_status,
        p.method AS payment_method,
        p.amount AS payment_amount,
        p.payment_date,
        ${proofUrlSelect} AS proof_url,
        p.notes
      FROM orders o
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN LATERAL (
        SELECT p.*
        FROM payments p
        WHERE p.order_id = o.order_id
        ORDER BY p.payment_date DESC NULLS LAST, p.payment_id DESC
        LIMIT 1
      ) p ON TRUE
      WHERE o.customer_id = $1
    `;

    const params = [id];
    let idx = 2;

    if (branch_id) {
      query += ` AND o.branch_id = $${idx++}`;
      params.push(branch_id);
    }

    query += ` ORDER BY o.created_at DESC LIMIT $${idx++} OFFSET $${idx++}`;
    params.push(lim, off);

    const result = await db.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching customer transactions:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// Endpoint: POST /api/customers
router.post('/customers', async (req, res) => {
  try {
    const { name, email, phone, address, branch_id } = req.body;

    if (process.env.NODE_ENV === 'production') {
      console.log('Request received at POST /api/customers (fields: %s)', Object.keys(req.body || {}).join(', '));
    } else {
      console.log('Request received at POST /api/customers');
      console.log('Request body:', req.body);
      console.log('Connecting to database...');
    }

    // Validasi data
    if (!name || !phone) {
      return res.status(400).json({ success: false, message: 'Name and phone are required.' });
    }

    // Insert ke tabel customers (backward-compatible: only include columns that exist)
    const cols = ['name', 'phone', 'address'];
    const values = [name, phone, address || null];

    if (email !== undefined && (await customersHasColumn('email'))) {
      cols.push('email');
      values.push((email || null));
    }
    if (branch_id !== undefined && (await customersHasColumn('branch_id'))) {
      cols.push('branch_id');
      values.push((branch_id || null));
    }

    const placeholders = cols.map((_, i) => `$${i + 1}`).join(', ');
    const query = `
      INSERT INTO customers (${cols.join(', ')})
      VALUES (${placeholders})
      RETURNING *;
    `;
    const result = await db.query(query, values);

    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('Error adding customer:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Endpoint: PATCH /api/customers/:id
router.patch('/customers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, email, phone, address } = req.body;
    // Siapkan field yang akan diupdate
    const fields = [];
    const values = [];
    let idx = 1;

    if (name !== undefined) { fields.push(`name = $${idx++}`); values.push(name); }
    if (email !== undefined) { fields.push(`email = $${idx++}`); values.push(email); }
    if (phone !== undefined) { fields.push(`phone = $${idx++}`); values.push(phone); }
    if (address !== undefined) { fields.push(`address = $${idx++}`); values.push(address); }

    if (fields.length === 0) {
      return res.status(400).json({ success: false, message: 'No fields to update.' });
    }

    values.push(id);
    const query = `UPDATE customers SET ${fields.join(', ')} WHERE customer_id = $${idx} RETURNING *;`;
    const result = await db.query(query, values);

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// Endpoint: PUT /api/customers/:id
router.put('/customers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, email, phone, address } = req.body;

    // Validasi data
    if (!name || !address) {
      return res.status(400).json({ success: false, message: 'Name and address are required.' });
    }

    // Check if customer exists
    const existingCustomer = await db.query(
      'SELECT customer_id FROM customers WHERE customer_id = $1',
      [id]
    );

    if (existingCustomer.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    const query = `
      UPDATE customers
      SET name = $1, email = $2, phone = $3, address = $4, updated_at = CURRENT_TIMESTAMP
      WHERE customer_id = $5
      RETURNING *;
    `;
    const values = [name, email || null, phone || null, address, id];
    const result = await db.query(query, values);

    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('Error updating customer:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Endpoint: DELETE /api/customers/:id
router.delete('/customers/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Check if customer exists
    const existingCustomer = await db.query(
      'SELECT customer_id FROM customers WHERE customer_id = $1',
      [id]
    );

    if (existingCustomer.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    // Check if customer has related orders
    const orderCount = await db.query(
      'SELECT COUNT(*) FROM orders WHERE customer_id = $1',
      [id]
    );

    if (parseInt(orderCount.rows[0].count) > 0) {
      return res.status(400).json({ success: false, message: 'Cannot delete customer with existing orders.' });
    }

    await db.query('DELETE FROM customers WHERE customer_id = $1', [id]);

    res.json({ success: true, message: 'Customer deleted successfully' });
  } catch (err) {
    console.error('Error deleting customer:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

module.exports = router;
