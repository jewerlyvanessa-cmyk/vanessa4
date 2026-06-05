'use strict';

const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopOrderAssignedToTechnician,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopTechnicianApiRoutes(technicianApi, { db }) {
technicianApi.get("/dashboard", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }

    const hasPickupTd = await ordersHasPickupBranchColumn(db);
    const hasMetaTd = await ordersHasMetadataColumn(db);
    const brScopeTd = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupTd, hasMetaTd);

    const userIdTd = parseInt(String(req.query.user_id ?? ''), 10);
    const userIdTdOk = Number.isFinite(userIdTd) && userIdTd > 0;

    const queueStatusesTd = sqlWorkshopTukangQueueStatuses('o');
    const unassTd = sqlWorkshopOrderIsUnassigned('o', hasMetaTd);
    const assTd = sqlWorkshopOrderAssignedToTechnician('o', 2, hasMetaTd);

    let statsResult;
    if (hasMetaTd && userIdTdOk) {
      statsResult = await db.query(
        `
      SELECT
        COUNT(*) FILTER (
          WHERE (${queueStatusesTd}) AND (${unassTd})
        )::int AS pending_work_orders,
        COUNT(*) FILTER (
          WHERE (${queueStatusesTd}) AND (${assTd})
        )::int AS in_progress_work_orders,
        COUNT(*) FILTER (
          WHERE o.status::text IN ('completed', 'delivered', 'done_workshop', 'ready_for_pickup')
        )::int AS completed_work_orders
      FROM orders o
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND DATE(o.created_at) = CURRENT_DATE
    `,
        [branchId, userIdTd]
      );
    } else {
      statsResult = await db.query(
        `
      SELECT
        COUNT(CASE WHEN o.status::text IN ('in_workshop', 'repairing', 'polishing', 'custom_work', 'sent-to-workshop') THEN 1 END) as pending_work_orders,
        COUNT(CASE WHEN o.status::text IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_work_orders,
        COUNT(CASE WHEN o.status::text IN ('completed', 'delivered', 'done_workshop', 'ready_for_pickup') THEN 1 END) as completed_work_orders
      FROM orders o
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND DATE(o.created_at) = CURRENT_DATE
    `,
        [branchId]
      );
    }

    const stats = statsResult.rows[0];

    // Recent assignments — item dari order_items (kolom orders.item_id tidak lagi dipakai).
    const recentAssignmentsResult = await db.query(`
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        sub.item_name,
        c.name as customer_name
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN LATERAL (
        SELECT COALESCE(oi.nama_item, i.name) AS item_name
        FROM order_items oi
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE oi.order_id = o.order_id
        LIMIT 1
      ) sub ON true
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND o.status::text IN ('in_workshop', 'repairing', 'polishing', 'custom_work', 'sent-to-workshop')
      ORDER BY o.created_at DESC
      LIMIT 5
    `, [branchId]);

    const recentAssignments = recentAssignmentsResult.rows.map((row) => ({
      order_id: row.order_id != null ? String(row.order_id) : null,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      item_name: row.item_name,
      customer_name: row.customer_name,
    }));

    const response = {
      pending_work_orders: parseInt(stats.pending_work_orders, 10) || 0,
      in_progress_work_orders: parseInt(stats.in_progress_work_orders, 10) || 0,
      completed_work_orders: parseInt(stats.completed_work_orders, 10) || 0,
      recent_assignments: recentAssignments,
      last_updated: new Date().toISOString(),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching technician dashboard:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});
}

module.exports = { registerWorkshopTechnicianApiRoutes };
