const express = require('express');
const pool = require('../db');

const router = express.Router();

// GET /api/branches - Get all branches
router.get('/branches', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        created_at,
        updated_at
      FROM branches
      ORDER BY name ASC
    `);
    const rows = result.rows.map((row) => ({
      branch_id: row.branch_id != null ? String(row.branch_id) : '',
      name: row.name,
      code: row.code,
      alias: row.alias,
      initials: row.initials,
      address: row.address,
      phone_number: row.phone_number,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
    }));
    res.json(rows);
  } catch (err) {
    console.error('Error fetching branches:', err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

// GET /api/branches/:id - Get branch by ID
router.get('/branches/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(`
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error fetching branch:', err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

// POST /api/branches - Create new branch
router.post('/branches', async (req, res) => {
  try {
    const { name, code, alias, initials, address, phone_number } = req.body;

    // Validate required fields
    if (!name || !code) {
      return res.status(400).json({ error: 'Name and code are required' });
    }

    // Check if code already exists
    const existingBranch = await pool.query(
      'SELECT branch_id FROM branches WHERE code = $1',
      [code]
    );

    if (existingBranch.rows.length > 0) {
      return res.status(400).json({ error: 'Branch code already exists' });
    }

    const result = await pool.query(`
      INSERT INTO branches (name, code, alias, initials, address, phone_number, status)
      VALUES ($1, $2, $3, $4, $5, $6, 'active')
      RETURNING *
    `, [name, code, alias, initials, address, phone_number]);

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating branch:', err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

// PUT /api/branches/:id - Update branch
router.put('/branches/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, code, alias, initials, address, phone_number, status } = req.body;

    // Validate required fields
    if (!name || !code) {
      return res.status(400).json({ error: 'Name and code are required' });
    }

    // Check if branch exists
    const existingBranch = await pool.query(
      'SELECT branch_id FROM branches WHERE branch_id = $1',
      [id]
    );

    if (existingBranch.rows.length === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    // Check if code already exists for another branch
    const codeCheck = await pool.query(
      'SELECT branch_id FROM branches WHERE code = $1 AND branch_id != $2',
      [code, id]
    );

    if (codeCheck.rows.length > 0) {
      return res.status(400).json({ error: 'Branch code already exists' });
    }

    const result = await pool.query(`
      UPDATE branches
      SET name = $1, code = $2, alias = $3, initials = $4, address = $5, phone_number = $6, status = $7, updated_at = CURRENT_TIMESTAMP
      WHERE branch_id = $8
      RETURNING *
    `, [name, code, alias, initials, address, phone_number, status || 'active', id]);

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error updating branch:', err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

// DELETE /api/branches/:id - Delete branch
router.delete('/branches/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Check if branch exists
    const existingBranch = await pool.query(
      'SELECT branch_id FROM branches WHERE branch_id = $1',
      [id]
    );

    if (existingBranch.rows.length === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    // Check if branch has related data (users, orders, etc.)
    const userCount = await pool.query(
      'SELECT COUNT(*) FROM user_branch_roles WHERE branch_id = $1',
      [id]
    );

    if (parseInt(userCount.rows[0].count) > 0) {
      return res.status(400).json({ error: 'Cannot delete branch with existing users' });
    }

    const orderCount = await pool.query(
      'SELECT COUNT(*) FROM orders WHERE branch_id = $1',
      [id]
    );

    if (parseInt(orderCount.rows[0].count) > 0) {
      return res.status(400).json({ error: 'Cannot delete branch with existing orders' });
    }

    await pool.query('DELETE FROM branches WHERE branch_id = $1', [id]);

    res.json({ message: 'Branch deleted successfully' });
  } catch (err) {
    console.error('Error deleting branch:', err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

module.exports = router;
