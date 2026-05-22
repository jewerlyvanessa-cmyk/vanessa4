'use strict';

const bcrypt = require('bcryptjs');

function registerUsersRoutes(app, deps) {
  const { db } = deps;
  app.get('/users', async (req, res) => {
    try {
      const query = `
        SELECT
          u.user_id,
          u.username,
          u.status,
          u.created_at,
          u.updated_at,
          ubr.role,
          b.name as branch_name,
          b.branch_id
        FROM users u
        LEFT JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
        LEFT JOIN branches b ON ubr.branch_id = b.branch_id
        ORDER BY u.username ASC
      `;
  
      const result = await db.query(query);
  
      // Group users by user_id and format the response
      const usersMap = new Map();
      result.rows.forEach(row => {
        const userId = row.user_id;
        if (!usersMap.has(userId)) {
          usersMap.set(userId, {
            user_id: row.user_id,
            username: row.username,
            status: row.status,
            created_at: row.created_at,
            updated_at: row.updated_at,
            branches: []
          });
        }
  
        if (row.role && row.branch_id) {
          usersMap.get(userId).branches.push({
            branch_id: row.branch_id,
            branch_name: row.branch_name,
            role: row.role,
            is_primary: row.is_primary || false
          });
        }
      });
  
      const users = Array.from(usersMap.values());
      res.json(users);
    } catch (error) {
      console.error('Error fetching users:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.post('/users', async (req, res) => {
    try {
      const { username, password, role, branch_id, is_primary = false } = req.body;
  
      if (!username || !password) {
        return res.status(400).json({ error: 'username and password are required' });
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
  
      // Insert user_branch_role if role and branch_id are provided
      if (role && branch_id) {
        const roleQuery = `
          INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
          VALUES ($1, $2, $3, $4)
        `;
        await db.query(roleQuery, [userId, branch_id, role, is_primary]);
      }
  
      res.status(201).json({ message: 'User created successfully', user_id: userId });
    } catch (error) {
      console.error('Error creating user:', error);
      if (error.code === '23505') { // Unique constraint violation
        res.status(400).json({ error: 'Username already exists' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  
  app.put('/users/:id', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { username, role, branch_id, is_primary, status } = req.body;
  
      if (!username) {
        return res.status(400).json({ error: 'username is required' });
      }
  
      // Update user basic info
      let userQuery = 'UPDATE users SET username = $1';
      const params = [username];
      let paramIndex = 2;
  
      if (status) {
        userQuery += `, status = $${paramIndex}`;
        params.push(status);
        paramIndex++;
      }
  
      userQuery += `, updated_at = now() WHERE user_id = $${paramIndex}`;
      params.push(id);
  
      await db.query(userQuery, params);
  
      // Update or insert user_branch_role if role and branch_id are provided
      if (role && branch_id) {
        // First, check if role already exists for this user and branch
        const existingRole = await db.query(
          'SELECT id FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
          [id, branch_id, role]
        );
  
        if (existingRole.rows.length > 0) {
          // Update existing role
          await db.query(
            'UPDATE user_branch_roles SET is_primary = $1 WHERE id = $2',
            [is_primary || false, existingRole.rows[0].id]
          );
        } else {
          // Insert new role
          await db.query(
            'INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary) VALUES ($1, $2, $3, $4)',
            [id, branch_id, role, is_primary || false]
          );
        }
      }
  
      res.json({ message: 'User updated successfully' });
    } catch (error) {
      console.error('Error updating user:', error);
      if (error.code === '23505') {
        res.status(400).json({ error: 'Username already exists' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  
  app.patch('/users/:id/password', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { password } = req.body ?? {};
      const newPassword = (password ?? '').toString();
      if (!newPassword.trim()) {
        return res.status(400).json({ error: 'password is required' });
      }
      if (newPassword.trim().length < 4) {
        return res.status(400).json({ error: 'password must be at least 4 characters' });
      }
  
      const hashedPassword = await bcrypt.hash(newPassword, 10);
      const result = await db.query(
        'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
        [hashedPassword, id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }
      res.json({ message: 'Password updated successfully' });
    } catch (error) {
      console.error('Error updating user password:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.patch('/users/:id/status', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { status } = req.body ?? {};
      const nextStatus = (status ?? '').toString().trim().toLowerCase();
      if (nextStatus !== 'active' && nextStatus !== 'inactive') {
        return res.status(400).json({ error: 'status must be active or inactive' });
      }
  
      const result = await db.query(
        'UPDATE users SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
        [nextStatus, id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }
      res.json({ message: 'User status updated successfully', status: nextStatus });
    } catch (error) {
      console.error('Error updating user status:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.delete('/users/:id', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
  
      // Delete user_branch_roles first (due to foreign key constraint)
      await db.query('DELETE FROM user_branch_roles WHERE user_id = $1', [id]);
  
      // Then delete the user
      const result = await db.query('DELETE FROM users WHERE user_id = $1', [id]);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }
  
      res.json({ message: 'User deleted successfully' });
    } catch (error) {
      console.error('Error deleting user:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // CRUD for User Branch Roles
  app.get('/user-branch-roles/:userId', async (req, res) => {
    try {
      const userId = parseInt(req.params.userId);
      const query = `
        SELECT
          ubr.id,
          ubr.user_id,
          ubr.branch_id,
          ubr.role,
          ubr.is_primary,
          b.name as branch_name
        FROM user_branch_roles ubr
        LEFT JOIN branches b ON ubr.branch_id = b.branch_id
        WHERE ubr.user_id = $1
        ORDER BY ubr.is_primary DESC, b.name ASC
      `;
  
      const result = await db.query(query, [userId]);
      res.json(result.rows);
    } catch (error) {
      console.error('Error fetching user branch roles:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.post('/user-branch-roles', async (req, res) => {
    try {
      const { user_id, branch_id, role, is_primary = false } = req.body;
  
      if (!user_id || !branch_id || !role) {
        return res.status(400).json({ error: 'user_id, branch_id, and role are required' });
      }
  
      // Check if role already exists for this user and branch
      const existingRole = await db.query(
        'SELECT id FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
        [user_id, branch_id, role]
      );
  
      if (existingRole.rows.length > 0) {
        return res.status(400).json({ error: 'Role already exists for this user and branch' });
      }
  
      // If setting as primary, unset other primary roles for this user
      if (is_primary) {
        await db.query(
          'UPDATE user_branch_roles SET is_primary = false WHERE user_id = $1',
          [user_id]
        );
      }
  
      const query = `
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
        RETURNING id
      `;
  
      const result = await db.query(query, [user_id, branch_id, role, is_primary]);
      res.status(201).json({
        message: 'User branch role created successfully',
        id: result.rows[0].id
      });
    } catch (error) {
      console.error('Error creating user branch role:', error);
      if (error.code === '23505') {
        res.status(400).json({ error: 'Role already exists for this user and branch' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  
  app.put('/user-branch-roles/:id', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { role, is_primary } = req.body;
  
      let query = 'UPDATE user_branch_roles SET';
      const params = [];
      let paramIndex = 1;
  
      if (role !== undefined) {
        query += ` role = $${paramIndex}`;
        params.push(role);
        paramIndex++;
      }
  
      if (is_primary !== undefined) {
        if (params.length > 0) query += ',';
        query += ` is_primary = $${paramIndex}`;
        params.push(is_primary);
  
        // If setting as primary, unset other primary roles for this user
        if (is_primary) {
          const userResult = await db.query('SELECT user_id FROM user_branch_roles WHERE id = $1', [id]);
          if (userResult.rows.length > 0) {
            await db.query(
              'UPDATE user_branch_roles SET is_primary = false WHERE user_id = $1 AND id != $2',
              [userResult.rows[0].user_id, id]
            );
          }
        }
      }
  
      if (params.length === 0) {
        return res.status(400).json({ error: 'No fields to update' });
      }
  
      query += ` WHERE id = $${paramIndex}`;
      params.push(id);
  
      const result = await db.query(query, params);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User branch role not found' });
      }
  
      res.json({ message: 'User branch role updated successfully' });
    } catch (error) {
      console.error('Error updating user branch role:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.delete('/user-branch-roles/:userId/:branchId/:role', async (req, res) => {
    try {
      const userId = parseInt(req.params.userId);
      const branchId = parseInt(req.params.branchId);
      const role = req.params.role;
  
      const result = await db.query(
        'DELETE FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
        [userId, branchId, role]
      );
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'User branch role not found' });
      }
  
      res.json({ message: 'User branch role deleted successfully' });
    } catch (error) {
      console.error('Error deleting user branch role:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

}

module.exports = { registerUsersRoutes };
