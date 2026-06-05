'use strict';

const {
  ordersHasMetadataColumn,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopAntrianVisibleAtBranch,
  ordersHasMetadataColumnLive,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopDashboardRoutes(workshopApi, { db }) {
workshopApi.get("/dashboard", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }

    const hasMetaDash = await ordersHasMetadataColumnLive(db);
    const brScopeDash = sqlWorkshopAntrianVisibleAtBranch('o', 1, hasMetaDash);
    const queueStatusesDash = sqlWorkshopTukangQueueStatuses('o');
    const unassDash = sqlWorkshopOrderIsUnassigned('o', hasMetaDash);
    const inProgressDash = hasMetaDash
      ? `(
          o.status::text IN ('repairing', 'polishing', 'custom_work')
          OR (
            o.status::text = 'in_workshop'
            AND NOT (${sqlWorkshopOrderIsUnassigned('o', hasMetaDash)})
          )
        )`
      : `o.status::text IN ('repairing', 'polishing', 'custom_work', 'in_workshop')`;

    // Selaras GET /workshop-orders: antrian = belum assign; ON PROGRESS = sedang dikerjakan.
    const statsResult = await db.query(
      `
      SELECT
        COUNT(*) FILTER (
          WHERE (${queueStatusesDash}) AND (${unassDash})
        )::int AS pending_orders,
        COUNT(*) FILTER (
          WHERE (${inProgressDash})
        )::int AS in_progress_orders,
        COUNT(*) FILTER (
          WHERE o.status::text IN ('done_workshop', 'ready_for_pickup', 'completed', 'delivered')
            AND DATE(o.updated_at) = CURRENT_DATE
        )::int AS completed_orders
      FROM orders o
      WHERE ${brScopeDash}
        AND o.order_type::text IN ('service', 'custom')
    `,
      [branchId]
    );

    const stats = statsResult.rows[0];

    // Get recent orders
    const recentOrdersResult = await db.query(
      `
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        COALESCE(oi.nama_item, i.name) AS item_name,
        c.name AS customer_name
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE ${brScopeDash}
        AND o.order_type::text IN ('service', 'custom')
      ORDER BY o.created_at DESC
      LIMIT 5
    `,
      [branchId]
    );

    // Get technician count (simplified - count users with technician role in this branch)
    const technicianResult = await db.query(
      `
      SELECT COUNT(*)::int AS total_technicians
      FROM user_branch_roles ubr
      JOIN users u ON ubr.user_id = u.user_id
      WHERE ubr.branch_id = $1 AND ubr.role = 'tukang' AND u.status = 'active'
    `,
      [branchId]
    );

    const technicianCount = technicianResult.rows[0]?.total_technicians || 0;

    const response = {
      pending_orders: parseInt(stats.pending_orders) || 0,
      in_progress_orders: parseInt(stats.in_progress_orders) || 0,
      completed_orders: parseInt(stats.completed_orders) || 0,
      total_technicians: technicianCount,
      active_technicians: technicianCount, // Simplified
      recent_orders: recentOrdersResult.rows,
      last_updated: new Date().toISOString(),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching workshop dashboard:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.get("/reports", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ""), 10);
    const periodRaw = String(req.query.period ?? "month").toLowerCase();
    const period = ["week", "month", "year", "quarter"].includes(periodRaw)
      ? periodRaw
      : "month";

    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: "branch_id wajib diisi dan valid" });
    }

    let dateFilter = "";
    if (period === "week") {
      dateFilter = "AND o.created_at >= DATE_TRUNC('week', CURRENT_DATE)";
    } else if (period === "year") {
      dateFilter = "AND o.created_at >= DATE_TRUNC('year', CURRENT_DATE)";
    } else if (period === "quarter") {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    } else {
      dateFilter = "AND o.created_at >= DATE_TRUNC('month', CURRENT_DATE)";
    }

    const hasOrdersMetadata = await ordersHasMetadataColumn(db);
    const technicianExpr = hasOrdersMetadata
      ? "COALESCE(NULLIF(o.metadata->>'assigned_technician', ''), NULLIF(o.metadata->>'assigned_technician_id', ''), 'Unassigned')"
      : "'Unassigned'";
    const sellingPriceExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'selling_price')::numeric, 0)"
      : "0::numeric";
    const buybackPriceExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'buyback_price')::numeric, 0)"
      : "0::numeric";
    const materialCostExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'material_cost')::numeric, 0)"
      : "0::numeric";
    const laborCostExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'labor_cost')::numeric, 0)"
      : "0::numeric";

    const orderStats = await db.query(
      `
        SELECT
          COUNT(*) as total_orders,
          COUNT(CASE WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered') THEN 1 END) as completed_orders,
          COUNT(CASE WHEN o.status IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_orders,
          COUNT(CASE WHEN o.status IN ('pending', 'sent-to-workshop', 'in_workshop') THEN 1 END) as pending_orders,
          AVG(
            CASE
              WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
              THEN EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
              ELSE NULL
            END
          ) as avg_completion_hours
        FROM orders o
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          ${dateFilter}
      `,
      [branchId]
    );

    const technicianStats = await db.query(
      `
        SELECT
          ${technicianExpr} as technician,
          COUNT(*) as orders_assigned,
          COUNT(CASE WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered') THEN 1 END) as orders_completed,
          AVG(
            CASE
              WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
              THEN EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
              ELSE NULL
            END
          ) as avg_time_hours
        FROM orders o
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          ${dateFilter}
        GROUP BY 1
        ORDER BY orders_assigned DESC
      `,
      [branchId]
    );

    const materialStats = await db.query(
      `
        SELECT
          COALESCE(
            NULLIF(BTRIM(oi.jenis), ''),
            NULLIF(BTRIM(i.material), ''),
            'Unknown'
          ) as material,
          SUM(COALESCE(oi.qty, 1)) as usage_count,
          SUM(COALESCE(oi.weight, i.weight, 0) * GREATEST(COALESCE(oi.qty, 1), 1)) as total_weight_used
        FROM orders o
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          AND o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
          ${dateFilter}
        GROUP BY 1
        ORDER BY total_weight_used DESC NULLS LAST
      `,
      [branchId]
    );

    const financialStats = await db.query(
      `
        SELECT
          SUM(CASE WHEN o.order_type = 'jual' THEN ${sellingPriceExpr} ELSE 0 END) as sales_revenue,
          SUM(CASE WHEN o.order_type = 'buyback' THEN ${buybackPriceExpr} ELSE 0 END) as buyback_revenue,
          SUM(${materialCostExpr}) as material_cost,
          SUM(${laborCostExpr}) as labor_cost
        FROM orders o
        WHERE o.branch_id = $1
          ${dateFilter}
      `,
      [branchId]
    );

    const stats = orderStats.rows[0] || {};
    const financial = financialStats.rows[0] || {};
    const totalOrders = parseInt(stats.total_orders || 0, 10) || 0;
    const completedOrders = parseInt(stats.completed_orders || 0, 10) || 0;
    const inProgressOrders = parseInt(stats.in_progress_orders || 0, 10) || 0;
    const pendingOrders = parseInt(stats.pending_orders || 0, 10) || 0;
    const avgCompletionHours = parseFloat(stats.avg_completion_hours || 0) || 0;

    const totalMaterialUsed = materialStats.rows.reduce(
      (acc, row) => acc + (parseFloat(row.total_weight_used || 0) || 0),
      0
    );
    const materialTypes = materialStats.rows.filter(
      (row) => String(row.material ?? '').trim().length > 0
    ).length;
    const materialEfficiency = totalOrders > 0
      ? (completedOrders / totalOrders) * 100
      : 0;
    const activeTechnicians = technicianStats.rows.filter(
      (row) => (parseInt(row.orders_assigned || 0, 10) || 0) > 0
    ).length;

    const salesRevenue = parseFloat(financial.sales_revenue || 0) || 0;
    const buybackRevenue = parseFloat(financial.buyback_revenue || 0) || 0;
    const materialCost = parseFloat(financial.material_cost || 0) || 0;
    const laborCost = parseFloat(financial.labor_cost || 0) || 0;

    res.status(200).json({
      // Flat keys for legacy/mobile UI compatibility
      total_orders: totalOrders,
      completed_orders: completedOrders,
      in_progress_orders: inProgressOrders,
      pending_orders: pendingOrders,
      avg_production_time: avgCompletionHours,
      total_material_used: totalMaterialUsed,
      material_types: materialTypes,
      material_efficiency: materialEfficiency,
      total_technicians: technicianStats.rows.length,
      active_technicians: activeTechnicians,

      // Rich structure for newer UI/widgets
      period,
      order_summary: {
        total_orders: totalOrders,
        completed_orders: completedOrders,
        in_progress_orders: inProgressOrders,
        pending_orders: pendingOrders,
        avg_completion_time: `${Math.round(avgCompletionHours * 10) / 10} jam`,
      },
      technician_performance: technicianStats.rows,
      material_usage: materialStats.rows,
      financial_summary: {
        total_revenue: salesRevenue + buybackRevenue,
        total_cost: materialCost + laborCost,
        net_profit: (salesRevenue + buybackRevenue) - (materialCost + laborCost),
      },
    });
  } catch (error) {
    console.error("Error fetching workshop reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

}

module.exports = { registerWorkshopDashboardRoutes };
