const express = require('express');
const router = express.Router();
const db = require('../db');

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

// Endpoint: POST /api/customers
router.post('/customers', async (req, res) => {
  try {
    const { name, email, phone, address, branch_id } = req.body;

    console.log('Request received at POST /api/customers');
    console.log('Request body:', req.body); // Log request body
    console.log('Connecting to database...');

    // Validasi data
    if (!name || !phone) {
      return res.status(400).json({ success: false, message: 'Name and phone are required.' });
    }

    // Insert ke tabel customers
    const query = `
      INSERT INTO customers (name, phone, address)
      VALUES ($1, $2, $3)
      RETURNING *;
    `;
    const values = [name, phone, address || null];
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
