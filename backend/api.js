const express = require('express');
const pool = require('./db');

const router = express.Router();

// Endpoint untuk mendapatkan semua data
router.get('/data', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM data');
    res.json(result.rows);
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

// Endpoint untuk menambahkan data baru
router.post('/data', async (req, res) => {
  const { name, value } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO data (name, value) VALUES ($1, $2) RETURNING *',
      [name, value]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

// Endpoint untuk memperbarui data
router.put('/data/:id', async (req, res) => {
  const { id } = req.params;
  const { name, value } = req.body;
  try {
    const result = await pool.query(
      'UPDATE data SET name = $1, value = $2 WHERE id = $3 RETURNING *',
      [name, value, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

// Endpoint untuk menghapus data
router.delete('/data/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM data WHERE id = $1', [id]);
    res.status(204).send();
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

module.exports = router;
