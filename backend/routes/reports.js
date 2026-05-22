'use strict';

function registerReportsRoutes(app, deps) {
  const { db } = deps;

  /** Manajer: daftar order completed hari ini dari semua branch */
  app.get('/reports/orders-completed-today', async (req, res) => {
    try {
      const { limit } = req.query;

      let query = `
        SELECT
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.total,
          o.diskon,
          o.mode,
          o.created_at,
          o.updated_at,
          o.branch_id,
          b.name as branch_name,
          o.user_id,
          u.username as created_by_username,
          o.customer_id,
          c.name as customer_name,
          c.phone as customer_phone
        FROM orders o
        LEFT JOIN branches b ON o.branch_id = b.branch_id
        LEFT JOIN users u ON o.user_id = u.user_id
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        WHERE DATE(o.created_at) = CURRENT_DATE
          AND o.status = 'completed'
        ORDER BY o.created_at DESC
      `;

      const params = [];
      if (limit) {
        query += ` LIMIT $1`;
        params.push(parseInt(limit, 10));
      }

      const result = await db.query(query, params);
      const processed = result.rows.map((r) => ({
        ...r,
        order_id: r.order_id?.toString?.() ?? r.order_id,
        branch_id: r.branch_id?.toString?.() ?? r.branch_id,
        user_id: r.user_id?.toString?.() ?? r.user_id,
        customer_id: r.customer_id?.toString?.() ?? r.customer_id,
        total: r.total == null ? null : parseFloat(r.total),
        total_akhir: r.total == null ? null : parseFloat(r.total),
        diskon: r.diskon == null ? null : parseFloat(r.diskon),
      }));

      res.status(200).json(processed);
    } catch (error) {
      console.error('Error fetching completed orders today:', error);
      res.status(500).json({ error: 'Internal server error', detail: error.message });
    }
  });
}

module.exports = { registerReportsRoutes };
