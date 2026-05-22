'use strict';

const {
  normalizeBranchType,
  ensureBranchesBranchTypeColumn,
} = require('../lib/branches_schema');
const { handleBranchesListGet } = require('../lib/branches_list_handler');
const { handleBranchLogoGet } = require('../lib/branch_logo_http_lazy');

function registerBranchesServerRoutes(app, deps) {
  const { db, requireRoles, upload } = deps;
  app.get('/branches', (req, res) => handleBranchesListGet(req, res, db));
  app.post('/branches', requireRoles('superadmin'), async (req, res) => {
    try {
      const { name, code, alias, initials, address, phone_number } = req.body;
  
      if (!name || !code) {
        return res.status(400).json({ error: 'name and code are required' });
      }
  
      await ensureBranchesBranchTypeColumn(db);
      const branchType = normalizeBranchType(req.body.branch_type);
      const { logo_url } = req.body || {};
      const insertQuery = `
        INSERT INTO branches (name, code, alias, initials, address, phone_number, status, branch_type, logo_url, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, 'active', $7, $8, NOW(), NOW())
        RETURNING branch_id, name, code, alias, initials, address, phone_number, status, branch_type, logo_url, created_at, updated_at
      `;
      const result = await db.query(insertQuery, [
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        branchType,
        logo_url || null,
      ]);
  
      res.status(201).json(result.rows[0]);
    } catch (error) {
      console.error('Error creating branch:', error);
      if (error.code === '23505') {
        res.status(400).json({ error: 'Branch code already exists' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  app.get('/branches/:id/basic', async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const qWithLogo = `
        SELECT
          branch_id,
          name,
          code,
          alias,
          initials,
          address,
          phone_number,
          status,
          logo_url,
          created_at,
          updated_at
        FROM branches
        WHERE branch_id = $1
      `;
      const qNoLogo = `
        SELECT
          branch_id,
          name,
          code,
          alias,
          initials,
          address,
          phone_number,
          status,
          NULL::text AS logo_url,
          created_at,
          updated_at
        FROM branches
        WHERE branch_id = $1
      `;
      let result;
      try {
        result = await db.query(qWithLogo, [id]);
      } catch (e) {
        if (String(e.message || '').includes('logo_url')) {
          result = await db.query(qNoLogo, [id]);
        } else {
          throw e;
        }
      }
  
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
  
      res.json(result.rows[0]);
    } catch (error) {
      console.error('Error fetching branch:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.get('/branches/:id/users', async (req, res) => {
    try {
      const branchId = parseInt(req.params.id);
      const query = `
        SELECT
          u.user_id,
          u.username,
          u.status as user_status,
          ubr.role,
          ubr.is_primary
        FROM users u
        JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
        WHERE ubr.branch_id = $1
        ORDER BY ubr.is_primary DESC, u.username ASC
      `;
  
      const result = await db.query(query, [branchId]);
      res.json(result.rows);
    } catch (error) {
      console.error('Error fetching branch users:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.get('/branches/:id/statistics', async (req, res) => {
    try {
      const branchId = parseInt(req.params.id);
  
      // Get user count
      const userQuery = 'SELECT COUNT(*) as count FROM user_branch_roles WHERE branch_id = $1';
      const userResult = await db.query(userQuery, [branchId]);
      const totalUsers = parseInt(userResult.rows[0].count);
  
      // Get transaction count (this month)
      const transactionQuery = `
        SELECT COUNT(*) as count
        FROM orders
        WHERE branch_id = $1
        AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
      `;
      const transactionResult = await db.query(transactionQuery, [branchId]);
      const totalTransactions = parseInt(transactionResult.rows[0].count);
  
      // Get items count in this branch
      const itemsQuery = 'SELECT COUNT(*) as count FROM items WHERE branch_id = $1';
      const itemsResult = await db.query(itemsQuery, [branchId]);
      const totalItems = parseInt(itemsResult.rows[0].count);
  
      // Get completed orders this month
      const completedOrdersQuery = `
        SELECT COUNT(*) as count
        FROM orders
        WHERE branch_id = $1
        AND status = 'completed'
        AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
      `;
      const completedResult = await db.query(completedOrdersQuery, [branchId]);
      const completedOrders = parseInt(completedResult.rows[0].count);
  
      res.json({
        total_users: totalUsers,
        total_transactions: totalTransactions,
        total_items: totalItems,
        completed_orders_this_month: completedOrders
      });
    } catch (error) {
      console.error('Error fetching branch statistics:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.get('/branches/:id/logo', (req, res) => handleBranchLogoGet(req, res, db));
  
  app.get('/branches/:id', async (req, res) => {
    try {
      await ensureBranchesBranchTypeColumn(db);
      const id = parseInt(req.params.id);
      const qWithLogo = `
        SELECT
          branch_id,
          name,
          code,
          alias,
          initials,
          address,
          phone_number,
          status,
          branch_type,
          logo_url,
          created_at,
          updated_at
        FROM branches
        WHERE branch_id = $1
      `;
      const qNoLogo = `
        SELECT
          branch_id,
          name,
          code,
          alias,
          initials,
          address,
          phone_number,
          status,
          branch_type,
          NULL::text AS logo_url,
          created_at,
          updated_at
        FROM branches
        WHERE branch_id = $1
      `;
      let result;
      try {
        result = await db.query(qWithLogo, [id]);
      } catch (e) {
        if (String(e.message || '').includes('logo_url')) {
          result = await db.query(qNoLogo, [id]);
        } else {
          throw e;
        }
      }
  
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
  
      const row = result.rows[0];
      res.json({
        ...row,
        branch_type: normalizeBranchType(row.branch_type),
      });
    } catch (error) {
      console.error('Error fetching branch:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.put('/branches/:id', requireRoles('superadmin'), async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { name, code, alias, initials, address, phone_number } = req.body;
  
      if (!name || !code) {
        return res.status(400).json({ error: 'name and code are required' });
      }
  
      await ensureBranchesBranchTypeColumn(db);
      const prevTypeRes = await db.query(
        'SELECT branch_type FROM branches WHERE branch_id = $1',
        [id],
      );
      const prevType =
        prevTypeRes.rows[0]?.branch_type != null
          ? normalizeBranchType(prevTypeRes.rows[0].branch_type)
          : 'toko';
      const branchType =
        req.body.branch_type !== undefined && req.body.branch_type !== null
          ? normalizeBranchType(req.body.branch_type)
          : prevType;
      const query = `
        UPDATE branches
        SET name = $1, code = $2, alias = $3, initials = $4, address = $5, phone_number = $6,
            branch_type = $7, updated_at = now()
        WHERE branch_id = $8
      `;
  
      const result = await db.query(query, [
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        branchType,
        id,
      ]);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
  
      res.json({ message: 'Branch updated successfully' });
    } catch (error) {
      console.error('Error updating branch:', error);
      if (error.code === '23505') {
        res.status(400).json({ error: 'Branch code already exists' });
      } else {
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
  
  app.patch('/branches/:id/status', requireRoles('superadmin'), async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { status } = req.body;
  
      if (!status || !['active', 'inactive'].includes(status)) {
        return res.status(400).json({ error: 'Valid status (active/inactive) is required' });
      }
  
      const query = 'UPDATE branches SET status = $1, updated_at = now() WHERE branch_id = $2';
  
      const result = await db.query(query, [status, id]);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
  
      res.json({ message: 'Branch status updated successfully' });
    } catch (error) {
      console.error('Error updating branch status:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Upload / hapus logo cabang (multipart field name: `logo`)
  async function ensureBranchesLogoColumn() {
    await db.query('ALTER TABLE branches ADD COLUMN IF NOT EXISTS logo_url TEXT');
  }
  
  app.post(
    '/branches/:id/logo',
    requireRoles('superadmin'),
    (req, res, next) => {
      upload.single('logo')(req, res, (err) => {
        if (err) {
          return res.status(400).json({ error: err.message || 'Upload failed' });
        }
        next();
      });
    },
    async (req, res) => {
      try {
        await ensureBranchesLogoColumn();
        const id = parseInt(req.params.id, 10);
        if (!Number.isFinite(id)) {
          return res.status(400).json({ error: 'Invalid branch id' });
        }
        if (!req.file) {
          return res.status(400).json({ error: 'File logo wajib diisi (field: logo)' });
        }
        const urlPath = `/uploads/${req.file.filename}`;
        const result = await db.query(
          `UPDATE branches SET logo_url = $1, updated_at = now() WHERE branch_id = $2 RETURNING branch_id, logo_url`,
          [urlPath, id]
        );
        if (result.rowCount === 0) {
          return res.status(404).json({ error: 'Branch not found' });
        }
        res.status(200).json({ branch_id: String(id), logo_url: result.rows[0].logo_url });
      } catch (error) {
        console.error('Error uploading branch logo:', error);
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  );
  
  app.delete('/branches/:id/logo', requireRoles('superadmin'), async (req, res) => {
    try {
      await ensureBranchesLogoColumn();
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id)) {
        return res.status(400).json({ error: 'Invalid branch id' });
      }
      const result = await db.query(
        `UPDATE branches SET logo_url = NULL, updated_at = now() WHERE branch_id = $1 RETURNING branch_id`,
        [id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
      res.json({ message: 'Logo cabang dihapus', branch_id: String(id) });
    } catch (error) {
      console.error('Error clearing branch logo:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.delete('/branches/:id', requireRoles('superadmin'), async (req, res) => {
    try {
      const id = parseInt(req.params.id);
  
      // Check if branch has users assigned
      const userCheck = await db.query('SELECT COUNT(*) as count FROM user_branch_roles WHERE branch_id = $1', [id]);
      if (parseInt(userCheck.rows[0].count) > 0) {
        return res.status(400).json({ error: 'Cannot delete branch with assigned users' });
      }
  
      const result = await db.query('DELETE FROM branches WHERE branch_id = $1', [id]);
  
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
  
      res.json({ message: 'Branch deleted successfully' });
    } catch (error) {
      console.error('Error deleting branch:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Validate branch code uniqueness
  // Use a non-ambiguous path so it won't collide with /branches/:id
  app.get('/branches/validation/code', async (req, res) => {
    try {
      const { code, exclude } = req.query;
  
      if (!code) {
        return res.status(400).json({ error: 'Code parameter is required' });
      }
  
      let query = 'SELECT COUNT(*) as count FROM branches WHERE code = $1';
      const params = [code];
  
      if (exclude) {
        query += ' AND branch_id != $2';
        params.push(exclude);
      }
  
      const result = await db.query(query, params);
      const exists = parseInt(result.rows[0].count) > 0;
  
      res.json({ valid: !exists });
    } catch (error) {
      console.error('Error validating branch code:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Export branches
  app.get('/branches/export', async (req, res) => {
    try {
      const { format = 'csv' } = req.query;
  
      const query = 'SELECT * FROM branches ORDER BY name ASC';
      const result = await db.query(query);
  
      if (format === 'csv') {
        let csv = 'Branch ID,Name,Code,Alias,Initials,Address,Phone Number,Status,Created At,Updated At\n';
  
        result.rows.forEach(row => {
          csv += `${row.branch_id},"${row.name}","${row.code}","${row.alias || ''}","${row.initials || ''}","${row.address || ''}","${row.phone_number || ''}","${row.status}","${row.created_at}","${row.updated_at}"\n`;
        });
  
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename="branches.csv"');
        res.send(csv);
      } else {
        res.json(result.rows);
      }
    } catch (error) {
      console.error('Error exporting branches:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerBranchesServerRoutes };
