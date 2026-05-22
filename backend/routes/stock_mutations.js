'use strict';

function registerStockMutationsRoutes(app, deps) {
  const { db } = deps;
  app.get('/stock-mutations', async (req, res) => {
    try {
      const {
        branch_id,
        type,
        item_id,
        start_date,
        end_date,
        limit = 50,
        offset = 0,
        created_by,
        mine,
        reference_type,
      } = req.query;
  
      let query = `
        SELECT
          sm.*,
          i.name as item_name,
          i.material,
          i.purity,
          b.name as branch_name,
          u.username as created_by_name,
          o.order_type,
          o.order_number,
          o.created_at as order_created_at,
          cust.name as customer_name,
          cust.phone as customer_phone,
          ou.username as order_user_name,
          t.from_branch_id as transfer_from_branch_id,
          t.to_branch_id as transfer_to_branch_id,
          bfb.name as transfer_from_branch_name,
          btb.name as transfer_to_branch_name,
          appr.username as transfer_approved_by_username
        FROM stock_mutations sm
        LEFT JOIN items i ON sm.item_id = i.item_id
        LEFT JOIN branches b ON sm.branch_id = b.branch_id
        LEFT JOIN users u ON sm.created_by = u.user_id
        LEFT JOIN orders o
          ON sm.reference_type = 'order' AND sm.reference_id IS NOT NULL AND sm.reference_id = o.order_id
        LEFT JOIN customers cust ON o.customer_id = cust.customer_id
        LEFT JOIN users ou ON o.user_id = ou.user_id
        LEFT JOIN transfers t
          ON sm.reference_type = 'transfer' AND sm.reference_id IS NOT NULL AND sm.reference_id = t.transfer_id
        LEFT JOIN branches bfb ON t.from_branch_id = bfb.branch_id
        LEFT JOIN branches btb ON t.to_branch_id = btb.branch_id
        LEFT JOIN users appr ON t.approved_by = appr.user_id
        WHERE 1=1
      `;
  
      const params = [];
      let paramIndex = 1;
  
      const itemIdTrim = item_id != null ? String(item_id).trim() : '';
      const itemIdParsed =
        itemIdTrim !== '' ? parseInt(itemIdTrim, 10) : NaN;
      const itemScoped =
        Number.isFinite(itemIdParsed) && itemIdParsed > 0;
  
      // Filter cabang untuk daftar mutasi per cabang. Untuk riwayat per-item_id,
      // jangan filter branch_id — mutasi order di toko memakai branch_id toko,
      // sedangkan stockist gudang tetap perlu melihat alur penuh (transfer + jual).
      if (branch_id && !itemScoped) {
        query += ` AND sm.branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      }
  
      if (type) {
        query += ` AND sm.type = $${paramIndex}`;
        params.push(type);
        paramIndex++;
      }
  
      const refTypeTrim =
        reference_type != null ? String(reference_type).trim() : '';
      if (refTypeTrim) {
        query += ` AND sm.reference_type = $${paramIndex}`;
        params.push(refTypeTrim);
        paramIndex++;
      }
  
      const jwtUserIdMut = parseInt(
        String(req.user?.user_id ?? req.user?.id ?? '').trim(),
        10
      );
      const mineOnlyMut =
        mine === 'true' || mine === '1' || mine === true;
      const createdByMut = parseInt(String(created_by ?? '').trim(), 10);
      const roleNormMut = String(req.user?.role ?? '')
        .trim()
        .toLowerCase();
      const canFilterAnyUserMut = ['superadmin', 'manajer'].includes(roleNormMut);
  
      if (mineOnlyMut) {
        if (!Number.isFinite(jwtUserIdMut) || jwtUserIdMut <= 0) {
          return res.status(401).json({
            error: 'User login tidak dikenali untuk filter mutasi',
          });
        }
        query += ` AND sm.created_by = $${paramIndex}`;
        params.push(jwtUserIdMut);
        paramIndex++;
      } else if (Number.isFinite(createdByMut) && createdByMut > 0) {
        if (!canFilterAnyUserMut && jwtUserIdMut !== createdByMut) {
          return res.status(403).json({
            error: 'Tidak boleh melihat mutasi pengguna lain',
          });
        }
        query += ` AND sm.created_by = $${paramIndex}`;
        params.push(createdByMut);
        paramIndex++;
      }
  
      if (itemScoped) {
        query += ` AND sm.item_id = $${paramIndex}`;
        params.push(itemIdParsed);
        paramIndex++;
      }
  
      const startDateTrim =
        start_date != null ? String(start_date).trim() : '';
      const endDateTrim = end_date != null ? String(end_date).trim() : '';
      if (startDateTrim) {
        query += ` AND DATE(sm.created_at) >= $${paramIndex}`;
        params.push(startDateTrim);
        paramIndex++;
      }
      if (endDateTrim) {
        query += ` AND DATE(sm.created_at) <= $${paramIndex}`;
        params.push(endDateTrim);
        paramIndex++;
      }
  
      const lim = Math.min(Math.max(parseInt(String(limit), 10) || 50, 1), 200);
      const off = Math.max(parseInt(String(offset), 10) || 0, 0);
      query += ` ORDER BY sm.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(lim, off);
  
      const result = await db.query(query, params);
      res.status(200).json(result.rows);
    } catch (error) {
      console.error('Error fetching stock mutations:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerStockMutationsRoutes };
