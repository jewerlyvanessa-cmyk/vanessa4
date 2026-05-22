'use strict';

const bcrypt = require('bcryptjs');

function registerEmployeesRoutes(app, deps) {
  const { db } = deps;
  app.get('/employees', async (req, res) => {
    try {
      const { branch_id, role, status } = req.query;
  
      let query = `
        SELECT
          u.user_id,
          u.username,
          u.status,
          ubr.role,
          ubr.is_primary,
          b.name as branch_name,
          u.created_at
        FROM users u
        JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
        LEFT JOIN branches b ON ubr.branch_id = b.branch_id
        WHERE 1=1
      `;
  
      const params = [];
      let paramIndex = 1;
  
      if (branch_id) {
        query += ` AND ubr.branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      }
  
      if (role) {
        query += ` AND ubr.role = $${paramIndex}`;
        params.push(role);
        paramIndex++;
      }
  
      if (status) {
        query += ` AND u.status = $${paramIndex}`;
        params.push(status);
        paramIndex++;
      }
  
      query += ` ORDER BY u.username ASC`;
  
      const result = await db.query(query, params);
      res.status(200).json(result.rows);
    } catch (error) {
      console.error('Error fetching employees:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Endpoint untuk menambah karyawan baru
  app.post('/employees', async (req, res) => {
    try {
      const { username, password, role, branch_id, is_primary = false } = req.body;
  
      if (!username || !password || !role || !branch_id) {
        return res.status(400).json({ error: 'username, password, role, and branch_id are required' });
      }
  
      // Hash password
      const saltRounds = 10;
      const hashedPassword = await bcrypt.hash(password, saltRounds);
  
      // Insert user
      const userQuery = `
        INSERT INTO users (username, password_hash, status)
        VALUES ($1, $2, 'active')
        RETURNING user_id
      `;
  
      const userResult = await db.query(userQuery, [username, hashedPassword]);
      const userId = userResult.rows[0].user_id;
  
      // Insert user_branch_role
      const roleQuery = `
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
      `;
  
      await db.query(roleQuery, [userId, branch_id, role, is_primary]);
  
      res.status(201).json({ message: 'Employee created successfully', user_id: userId });
    } catch (error) {
      console.error('Error creating employee:', error);
      if (error.code === '23505') { // Unique constraint violation
        res.status(400).json({ error: 'Username already exists' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  
  // Endpoint untuk update karyawan
  app.put('/employees/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const { username, role, status, is_primary } = req.body;
  
      // Update user
      if (username || status) {
        let userQuery = 'UPDATE users SET';
        const userParams = [];
        let userParamIndex = 1;
  
        if (username) {
          userQuery += ` username = $${userParamIndex}`;
          userParams.push(username);
          userParamIndex++;
        }
  
        if (status) {
          if (userParamIndex > 1) userQuery += ',';
          userQuery += ` status = $${userParamIndex}`;
          userParams.push(status);
          userParamIndex++;
        }
  
        userQuery += `, updated_at = CURRENT_TIMESTAMP WHERE user_id = $${userParamIndex}`;
        userParams.push(id);
  
        await db.query(userQuery, userParams);
      }
  
      // Update role
      if (role || is_primary !== undefined) {
        let roleQuery = 'UPDATE user_branch_roles SET';
        const roleParams = [];
        let roleParamIndex = 1;
  
        if (role) {
          roleQuery += ` role = $${roleParamIndex}`;
          roleParams.push(role);
          roleParamIndex++;
        }
  
        if (is_primary !== undefined) {
          if (roleParamIndex > 1) roleQuery += ',';
          roleQuery += ` is_primary = $${roleParamIndex}`;
          roleParams.push(is_primary);
          roleParamIndex++;
        }
  
        roleQuery += ` WHERE user_id = $${roleParamIndex}`;
        roleParams.push(id);
  
        await db.query(roleQuery, roleParams);
      }
  
      res.status(200).json({ message: 'Employee updated successfully' });
    } catch (error) {
      console.error('Error updating employee:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Endpoint untuk menghapus karyawan
  app.delete('/employees/:id', async (req, res) => {
    try {
      const { id } = req.params;
  
      // Delete user_branch_roles first (due to foreign key constraint)
      await db.query('DELETE FROM user_branch_roles WHERE user_id = $1', [id]);
  
      // Delete user
      const result = await db.query('DELETE FROM users WHERE user_id = $1', [id]);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Employee not found' });
      }
  
      res.status(200).json({ message: 'Employee deleted successfully' });
    } catch (error) {
      console.error('Error deleting employee:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerEmployeesRoutes };
