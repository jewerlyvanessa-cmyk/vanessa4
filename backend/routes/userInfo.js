const express = require('express');
const router = express.Router();
const db = require('../db'); // pastikan ada koneksi db

// Endpoint: GET /user-info
// Mengembalikan info user (role, branch) berdasarkan user yang sudah login (dari session/token)
router.get('/user-info', async (req, res) => {
  try {
    // User diambil dari JWT payload (lihat middleware/auth.js)
    const userId = req.user?.user_id ? parseInt(req.user.user_id, 10) : null;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    // Query role dan branch_id dari tabel user_branch_roles
    const result = await db.query(
      'SELECT role, branch_id FROM user_branch_roles WHERE user_id = $1 ORDER BY is_primary DESC NULLS LAST LIMIT 1',
      [userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User role not found' });
    }
    const { role, branch_id } = result.rows[0];
    res.json({ success: true, role, branch_id });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error', error: err.message });
  }
});

module.exports = router;
