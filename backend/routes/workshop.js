'use strict';

const express = require('express');
const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  orderCostBreakdownsTableExists,
  ordersEstimateColumns,
  sqlOrdersVisibleAtWorkshopBranch,
  orderVisibleAtWorkshopBranchId,
  sqlWorkshopTukangQueueStatuses,
  jsonSafeDbRow,
} = require('../lib/orders_workshop_helpers');

/**
 * Endpoint workshop / bengkel / teknisi (dipisah dari server.js).
 * Auth: /api/* dan /workshop-orders / /technicians diatur di server.js.
 */
function registerWorkshopRoutes(app, deps) {
  const { db } = deps;

  const workshopApi = express.Router();
  const technicianApi = express.Router();
workshopApi.get("/work-queue", async (req, res) => {
  try {
    const branchId = req.query.branch_id;
    const technicianIdRaw = req.query.technician_id;
    const technicianId = parseInt(String(technicianIdRaw ?? ''), 10);

    if (!branchId) {
      return res.status(400).json({ error: "branch_id is required" });
    }

    const hasPickupWq = await ordersHasPickupBranchColumn(db);
    const brScopeWq = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWq);
    // Satu baris per order + pelanggan + item utama (selaras GET /workshop-orders) agar UI tukang punya nama item & customer.
    let inner = `
      SELECT DISTINCT ON (o.order_id)
        o.*,
        c.name AS customer_name,
        c.phone AS customer_phone,
        COALESCE(oi.nama_item, i.name) AS item_name,
        COALESCE(oi.qty, 1) AS quantity,
        COALESCE(oi.weight, i.weight, 0) AS weight,
        COALESCE(oi.jenis, i.material) AS material
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE ${brScopeWq}
        AND o.order_type::text IN ('service', 'custom')
        AND ${sqlWorkshopTukangQueueStatuses('o')}
    `;
    const params = [branchId];
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    // tukang: tanpa technician_id = antrian cabang penuh; dengan technician_id = pekerjaan milik user/assignment saja.
    if (Number.isFinite(technicianId) && technicianId > 0) {
      const hasOrdersMetadata = await ordersHasMetadataColumn(db);
      if (role === 'tukang') {
        if (hasOrdersMetadata) {
          inner += ` AND (
          o.user_id = $2
          OR COALESCE(o.metadata->>'assigned_technician_id', '') = $2::text
          OR COALESCE(o.metadata->>'assigned_technician', '') = $2::text
        )`;
        } else {
          inner += ` AND o.user_id = $2`;
        }
        params.push(technicianId);
      } else if (hasOrdersMetadata) {
        inner += ` AND (
          o.user_id = $2
          OR COALESCE(o.metadata->>'assigned_technician_id', '') = $2::text
          OR COALESCE(o.metadata->>'assigned_technician', '') = $2::text
        )`;
        params.push(technicianId);
      } else if (role === 'superadmin' || role === 'admin_workshop' || role === 'manajer') {
        inner += ` AND o.user_id = $2`;
        params.push(technicianId);
      }
    }
    inner += `
      ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
    `;
    const query = `SELECT * FROM (${inner}) AS wq ORDER BY wq.created_at ASC`;

    const result = await db.query(query, params);
    const rows = result.rows.map((r) => {
      const row = jsonSafeDbRow(r);
      const est =
        row.estimated_time ??
        row.estimate_duration_text ??
        (row.metadata && typeof row.metadata === 'object' && row.metadata.estimasi_waktu
          ? row.metadata.estimasi_waktu
          : null);
      if (row.estimated_time == null && est != null) {
        row.estimated_time = est;
      }
      return row;
    });
    res.status(200).json(rows);
  } catch (error) {
    console.error("Error fetching work queue:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Service/custom: antrian di gudang/bengkel sebelum disetujui masuk workshop.
app.get('/api/workshop/service-incoming', async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (!new Set(['stockist', 'admin_workshop', 'superadmin', 'manajer']).has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan' });
    }
    const hasPickupSi = await ordersHasPickupBranchColumn(db);
    const brScopeSi = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupSi);
    const result = await db.query(
      `
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.branch_id,
          ${hasPickupSi ? 'o.pickup_branch_id,' : ''}
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          COALESCE(oi.nama_item, i.name) AS item_name
        FROM orders o
        JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.order_type::text IN ('service', 'custom')
          AND o.status::text = 'awaiting_warehouse'
          AND ${brScopeSi}
        ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
      `,
      [branchId]
    );
    const processedRows = result.rows.map((row) => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      branch_id: row.branch_id != null ? String(row.branch_id) : null,
      pickup_branch_id: hasPickupSi && row.pickup_branch_id != null
        ? String(row.pickup_branch_id)
        : null,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
    }));
    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching service incoming:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

workshopApi.get("/material-stock", async (req, res) => {
  try {
    const { branch_id } = req.query;
    console.log("Material stock request for branch_id:", branch_id, typeof branch_id);

    // Get material stock for workshop
    const result = await db.query(`
      SELECT
        item_id,
        name,
        material,
        purity,
        kategori,
        weight,
        quantity,
        status,
        COALESCE(metadata->>'location', 'Rak Umum') as location,
        COALESCE(metadata->>'min_stock', '0') as min_stock,
        COALESCE(metadata->>'supplier', 'N/A') as supplier,
        COALESCE(metadata->>'price_per_unit', '0') as price_per_unit,
        updated_at
      FROM items
      WHERE branch_id = $1
        AND stock_type = 'non_inventory'
        AND status IN ('ready', 'available', 'sold')
      ORDER BY material, name
    `, [branch_id]);

    console.log("Query result rows:", result.rows.length);
    console.log("First row sample:", result.rows[0]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      item_id: row.item_id.toString(),
      name: row.name,
      material: row.material,
      purity: row.purity,
      kategori: row.kategori,
      weight: parseFloat(row.weight || 0),
      quantity: parseInt(row.quantity || 0),
      status: row.status,
      location: row.location,
      min_stock: parseInt(row.min_stock || 0),
      supplier: row.supplier,
      price_per_unit: parseFloat(row.price_per_unit || 0),
      updated_at: row.updated_at
    }));

    const jsonResponse = JSON.stringify(processedRows);
    console.log("JSON length:", jsonResponse.length);

    res.status(200).json(processedRows);
  } catch (error) {
    console.error("Error fetching material stock:", error);
    console.error("Error stack:", error.stack);
    res.status(500).json({ error: "Internal server error", details: error.message });
  }
});

workshopApi.get("/dashboard", async (req, res) => {
  try {
    const { branch_id, user_id: _user_id } = req.query;

    // Get workshop statistics (consistent with other role dashboards)
    const statsResult = await db.query(`
      SELECT
        COUNT(CASE WHEN status IN ('in_workshop', 'repairing', 'polishing', 'custom_work') THEN 1 END) as pending_orders,
        COUNT(CASE WHEN status IN ('repairing', 'polishing') THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN status IN ('completed', 'delivered') THEN 1 END) as completed_orders
      FROM orders
      WHERE branch_id = $1
        AND order_type IN ('service', 'custom')
        AND DATE(created_at) = CURRENT_DATE
    `, [branch_id]);

    const stats = statsResult.rows[0];

    // Get recent orders
    const recentOrdersResult = await db.query(`
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        i.name as item_name,
        c.name as customer_name
      FROM orders o
      LEFT JOIN items i ON o.item_id = i.item_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
      ORDER BY o.created_at DESC
      LIMIT 5
    `, [branch_id]);

    // Get technician count (simplified - count users with technician role in this branch)
    const technicianResult = await db.query(`
      SELECT COUNT(*) as total_technicians
      FROM user_branch_roles ubr
      JOIN users u ON ubr.user_id = u.user_id
      WHERE ubr.branch_id = $1 AND ubr.role = 'tukang'
    `, [branch_id]);

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

workshopApi.get("/order-cost-breakdown", async (req, res) => {
  try {
    const orderId = parseInt(String(req.query.order_id ?? ""), 10);
    const branchId = parseInt(String(req.query.branch_id ?? ""), 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: "order_id tidak valid" });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: "branch_id wajib diisi" });
    }

    const hasPickupBreakdownGet = await ordersHasPickupBranchColumn(db);
    const orderRes = await db.query(
      `
        SELECT order_id, branch_id, order_type
          ${hasPickupBreakdownGet ? ", pickup_branch_id" : ""}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      return res.status(404).json({ error: "Order tidak ditemukan" });
    }
    const order = orderRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupBreakdownGet)) {
      return res.status(403).json({ error: "Order tidak untuk cabang workshop ini" });
    }
    const orderType = String(order.order_type ?? "").toLowerCase();
    if (orderType !== "service" && orderType !== "custom") {
      return res.status(400).json({ error: "Hanya order service/custom" });
    }

    const hasBreakdownTable = await orderCostBreakdownsTableExists(db);
    if (!hasBreakdownTable) {
      return res.status(200).json({ latest: null, history: [] });
    }

    const rows = await db.query(
      `
        SELECT
          breakdown_id,
          order_id,
          revision,
          material_cost,
          labor_cost,
          other_cost,
          notes,
          created_by,
          created_at
        FROM order_cost_breakdowns
        WHERE order_id = $1
        ORDER BY revision DESC
      `,
      [orderId]
    );
    const history = rows.rows.map((row) => ({
      ...row,
      breakdown_id: String(row.breakdown_id),
      order_id: String(row.order_id),
      revision: parseInt(row.revision ?? 0, 10) || 0,
      material_cost: parseFloat(row.material_cost ?? 0) || 0,
      labor_cost: parseFloat(row.labor_cost ?? 0) || 0,
      other_cost: parseFloat(row.other_cost ?? 0) || 0,
      created_by: row.created_by == null ? null : String(row.created_by),
    }));
    return res.status(200).json({
      latest: history.length > 0 ? history[0] : null,
      history,
    });
  } catch (error) {
    console.error("Error fetching order cost breakdown:", error);
    return res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.post("/order-cost-breakdown", async (req, res) => {
  const { order_id, branch_id, material_cost, labor_cost, other_cost, notes } = req.body ?? {};
  const orderId = parseInt(String(order_id ?? ""), 10);
  const branchId = parseInt(String(branch_id ?? ""), 10);
  if (!Number.isFinite(orderId) || orderId <= 0) {
    return res.status(400).json({ error: "order_id tidak valid" });
  }
  if (!Number.isFinite(branchId) || branchId <= 0) {
    return res.status(400).json({ error: "branch_id wajib diisi" });
  }

  const role = (req.user?.role ?? "").toString().trim().toLowerCase();
  const allowedRoles = new Set(["superadmin", "admin_toko", "admin_workshop", "tukang"]);
  if (!allowedRoles.has(role)) {
    return res.status(403).json({ error: "Role tidak diizinkan update biaya" });
  }

  const hasBreakdownTable = await orderCostBreakdownsTableExists(db);
  if (!hasBreakdownTable) {
    return res.status(400).json({ error: "Tabel order_cost_breakdowns belum tersedia" });
  }

  const materialCost = Math.max(0, parseFloat(String(material_cost ?? 0)) || 0);
  const laborCost = Math.max(0, parseFloat(String(labor_cost ?? 0)) || 0);
  const otherCost = Math.max(0, parseFloat(String(other_cost ?? 0)) || 0);
  const cleanNotes = String(notes ?? "").trim() || null;
  const updatedBy = parseInt(String(req.user?.user_id ?? req.body?.technician_id ?? 0), 10);
  const safeUpdatedBy = Number.isFinite(updatedBy) && updatedBy > 0 ? updatedBy : null;

  const client = await db.connect();
  let committed = false;
  try {
    await client.query("BEGIN");

    const hasPickupBreakdownPost = await ordersHasPickupBranchColumn(client);
    const orderRes = await client.query(
      `
        SELECT order_id, branch_id, order_type, status,
               COALESCE(diskon, 0)::float8 AS diskon
          ${hasPickupBreakdownPost ? ", pickup_branch_id" : ""}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ error: "Order tidak ditemukan" });
    }
    const order = orderRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupBreakdownPost)) {
      await client.query("ROLLBACK");
      return res.status(403).json({ error: "Order tidak untuk cabang workshop ini" });
    }
    const orderType = String(order.order_type ?? "").toLowerCase();
    if (orderType !== "service" && orderType !== "custom") {
      await client.query("ROLLBACK");
      return res.status(400).json({ error: "Hanya order service/custom" });
    }

    const st = (order.status ?? "").toString().trim().toLowerCase();
    const noCostEditStatuses = new Set(["cancelled", "completed", "sold"]);
    if (noCostEditStatuses.has(st)) {
      await client.query("ROLLBACK");
      return res.status(400).json({
        error: `Tidak bisa mengubah biaya pada status "${st}"`,
      });
    }

    const revRes = await client.query(
      `
        SELECT COALESCE(MAX(revision), 0) + 1 AS next_revision
        FROM order_cost_breakdowns
        WHERE order_id = $1
      `,
      [orderId]
    );
    const nextRevision = parseInt(revRes.rows?.[0]?.next_revision ?? 1, 10) || 1;

    const inserted = await client.query(
      `
        INSERT INTO order_cost_breakdowns (
          order_id,
          revision,
          material_cost,
          labor_cost,
          other_cost,
          notes,
          created_by
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *
      `,
      [orderId, nextRevision, materialCost, laborCost, otherCost, cleanNotes, safeUpdatedBy]
    );

    // Opsi B: selaraskan tagihan (orders.total) dengan breakdown — sama seperti POST /orders:
    // jumlah baris (dibulatkan ke kelipatan 5.000) lalu diskon level order.
    const preDiscountBase = materialCost + laborCost + otherCost;
    const diskonOrder = parseFloat(order.diskon) || 0;
    const lineRounded =
      preDiscountBase > 0 ? Math.ceil(preDiscountBase / 5000) * 5000 : 0;
    const newOrderTotal = lineRounded * (1 - diskonOrder / 100);

    const itemsRes = await client.query(
      `
        SELECT order_item_id
        FROM order_items
        WHERE order_id = $1
        ORDER BY order_item_id ASC
      `,
      [orderId]
    );
    if (itemsRes.rows.length > 0) {
      const firstId = itemsRes.rows[0].order_item_id;
      await client.query(
        `
          UPDATE order_items
          SET subtotal = $1,
              total = $2,
              diskon = 0
          WHERE order_item_id = $3
        `,
        [preDiscountBase, lineRounded, firstId]
      );
      if (itemsRes.rows.length > 1) {
        await client.query(
          `
            UPDATE order_items
            SET subtotal = 0,
                total = 0,
                diskon = 0
            WHERE order_id = $1
              AND order_item_id <> $2
          `,
          [orderId, firstId]
        );
      }
    }

    try {
      await client.query(
        `
          UPDATE orders
          SET total = $1,
              updated_at = NOW()
          WHERE order_id = $2
        `,
        [newOrderTotal, orderId]
      );
    } catch (updErr) {
      await client.query("ROLLBACK");
      console.error("order-cost-breakdown: update orders.total failed:", updErr);
      return res.status(500).json({ error: "Gagal memperbarui total order" });
    }

    const estCols = await ordersEstimateColumns(client);
    if (estCols.estimate_amount) {
      await client.query(
        `
          UPDATE orders
          SET estimate_amount = $1,
              updated_at = NOW()
          WHERE order_id = $2
        `,
        [preDiscountBase, orderId]
      );
    }

    const hasOrdersMetadata = await ordersHasMetadataColumn(client);
    if (hasOrdersMetadata) {
      await client.query(
        `
          UPDATE orders
          SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb,
              updated_at = NOW()
          WHERE order_id = $2
        `,
        [
          JSON.stringify({
            material_cost: materialCost,
            labor_cost: laborCost,
            other_cost: otherCost,
            actual_total_cost: preDiscountBase,
            invoice_pre_discount_rounded: lineRounded,
            order_total_after_discount: newOrderTotal,
            cost_revision: nextRevision,
            cost_updated_at: new Date().toISOString(),
          }),
          orderId,
        ]
      );
    }

    await client.query("COMMIT");
    committed = true;

    const row = inserted.rows[0] || {};
    return res.status(200).json({
      success: true,
      order_total: newOrderTotal,
      items_pre_discount_rounded: lineRounded,
      pre_discount_sum: preDiscountBase,
      breakdown: {
        ...row,
        breakdown_id: row.breakdown_id == null ? null : String(row.breakdown_id),
        order_id: row.order_id == null ? null : String(row.order_id),
        revision: parseInt(row.revision ?? 0, 10) || 0,
        material_cost: parseFloat(row.material_cost ?? 0) || 0,
        labor_cost: parseFloat(row.labor_cost ?? 0) || 0,
        other_cost: parseFloat(row.other_cost ?? 0) || 0,
        created_by: row.created_by == null ? null : String(row.created_by),
      },
    });
  } catch (error) {
    if (!committed) {
      try {
        await client.query("ROLLBACK");
      } catch (_) { /* ignore */ }
    }
    console.error("Error saving order cost breakdown:", error);
    return res.status(500).json({ error: "Internal server error" });
  } finally {
    try {
      client.release();
    } catch (_) { /* ignore */ }
  }
});

workshopApi.post("/update-progress", async (req, res) => {
  try {
    const { order_id, status, technician_id, notes, branch_id } = req.body;
    const orderId = parseInt(String(order_id ?? ''), 10);
    const branchId = parseInt(
      String(branch_id ?? req.query?.branch_id ?? ''),
      10
    );
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'admin_workshop',
      'tukang',
      'stockist',
    ]);
    if (!allowedRoles.has(role)) {
      return res
        .status(403)
        .json({ error: 'Role tidak diizinkan update progress workshop' });
    }

    const hasPickupProgress = await ordersHasPickupBranchColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupProgress ? ', pickup_branch_id' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupProgress)) {
      return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
    }
    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({
        error: 'Hanya order service/custom untuk workflow workshop',
      });
    }

    const incoming = (status ?? '').toString().trim().toLowerCase();
    const statusAlias = {
      pending: 'in_workshop',
      in_progress: 'repairing',
      completed: 'done_workshop',
    };
    const nextStatus = statusAlias[incoming] ?? incoming;

    const allowedByRole = {
      admin_toko: new Set(['awaiting_warehouse', 'ready_for_pickup']),
      stockist: new Set(['sent-to-workshop']),
      admin_workshop: new Set([
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'custom_work',
        'cancelled',
      ]),
      tukang: new Set([
        'in_workshop',
        'repairing',
        'polishing',
        'custom_work',
        'done_workshop',
        'cancelled',
      ]),
      superadmin: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
    };
    const roleAllowedSet = allowedByRole[role] ?? new Set();
    if (!roleAllowedSet.has(nextStatus)) {
      return res.status(400).json({
        error: `Status "${nextStatus}" tidak diizinkan untuk role ${role}`,
      });
    }

    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const validTransitions = {
      pending: new Set(['awaiting_warehouse']),
      confirmed: new Set(['awaiting_warehouse']),
      awaiting_warehouse: new Set(['sent-to-workshop']),
      'sent-to-workshop': new Set(['in_workshop']),
      in_workshop: new Set(['repairing', 'polishing', 'done_workshop']),
      repairing: new Set(['polishing', 'done_workshop']),
      polishing: new Set(['done_workshop']),
      custom_work: new Set(['done_workshop']),
      'done_workshop': new Set(['ready_for_pickup']),
      'ready_for_pickup': new Set(['completed']),
    };
    if (nextStatus === 'cancelled') {
      const mayCancel =
        (role === 'tukang' || role === 'admin_workshop' || role === 'superadmin') &&
        new Set([
          'pending',
          'confirmed',
          'awaiting_warehouse',
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work',
        ]).has(currentStatus);
      if (!mayCancel) {
        return res.status(400).json({
          error: `Pembatalan tidak diizinkan dari status "${currentStatus}"`,
        });
      }
    } else if (
      validTransitions[currentStatus] &&
      !validTransitions[currentStatus].has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      return res.status(400).json({
        error: `Transisi status tidak valid (${currentStatus} -> ${nextStatus})`,
      });
    }

    await db.query(`
      UPDATE orders
      SET status = $1, updated_at = NOW(),
          metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
      WHERE order_id = $3
    `, [nextStatus, JSON.stringify({
      "last_updated_by": technician_id,
      "last_update_notes": notes,
      "updated_at": new Date().toISOString()
    }), orderId]);

    res.status(200).json({ success: true, message: "Progress updated successfully" });
  } catch (error) {
    console.error("Error updating work progress:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.post("/update-stock", async (req, res) => {
  try {
    const { item_id, quantity, technician_id, notes } = req.body;

    await db.query(`
      UPDATE items
      SET quantity = $1, updated_at = NOW(),
          metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
      WHERE item_id = $3
    `, [quantity, JSON.stringify({
      "last_updated_by": technician_id,
      "last_update_notes": notes,
      "updated_at": new Date().toISOString()
    }), item_id]);

    res.status(200).json({ success: true, message: "Stock updated successfully" });
  } catch (error) {
    console.error("Error updating material stock:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.get("/work-history", async (req, res) => {
  try {
    const { technician_id: _technician_id, branch_id, period = 'all' } = req.query;

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = "AND DATE(o.created_at) = CURRENT_DATE";
    } else if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    }

    const result = await db.query(`
      SELECT
        o.order_id,
        o.status,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.kategori, i.kategori) as item_type,
        COALESCE(oi.qty, 1) as ordered_quantity,
        COALESCE(oi.weight, i.weight, 0) as weight,
        COALESCE(oi.jenis, i.material) as material,
        CASE
          WHEN o.status = 'completed' THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END as duration_hours
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.status IN ('completed', 'cancelled')
        ${dateFilter}
      ORDER BY o.updated_at DESC NULLS LAST, o.created_at DESC
      LIMIT 100
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
      item_type: row.item_type,
      ordered_quantity: parseInt(row.ordered_quantity || 0),
      weight: parseFloat(row.weight || 0),
      material: row.material,
      duration_hours: row.duration_hours ? parseFloat(row.duration_hours) : null
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error("Error fetching work history:", error);
    res.status(500).json({ error: "Internal server error", details: error.message });
  }
});

workshopApi.get("/technician-reports", async (req, res) => {
  try {
    const { technician_id: _technician_id, branch_id, period = 'month' } = req.query;

    let dateFilter = '';
    if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    } else if (period === 'quarter') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    }

    // Get work statistics
    const workStats = await db.query(`
      SELECT
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
        COUNT(CASE WHEN status IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN status IN ('in_workshop', 'sent-to-workshop') THEN 1 END) as pending_orders,
        AVG(CASE
          WHEN status = 'completed' THEN
            EXTRACT(EPOCH FROM (updated_at - created_at))/3600
          ELSE NULL
        END) as avg_duration_hours,
        SUM(CASE
          WHEN status = 'completed' THEN
            EXTRACT(EPOCH FROM (updated_at - created_at))/3600
          ELSE NULL
        END) as total_work_hours
      FROM orders
      WHERE branch_id = $1
        AND order_type IN ('service', 'custom')
        ${dateFilter.replace('o.created_at', 'created_at')}
    `, [branch_id]);

    // Get material usage statistics
    const materialStats = await db.query(`
      SELECT
        COALESCE(
          NULLIF(BTRIM(oi.jenis), ''),
          NULLIF(BTRIM(i.material), ''),
          'Unknown'
        ) as material_type,
        SUM(COALESCE(oi.weight, i.weight, 0) * COALESCE(oi.qty, 1)) as total_weight_used,
        SUM(COALESCE(oi.qty, 1)) as usage_count
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1 AND o.status = 'completed'
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY 1
      ORDER BY total_weight_used DESC
    `, [branch_id]);

    // Get daily work distribution
    const dailyStats = await db.query(`
      SELECT
        DATE(o.created_at) as work_date,
        COUNT(*) as orders_count,
        COUNT(CASE WHEN o.status = 'completed' THEN 1 END) as completed_count
      FROM orders o
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY DATE(o.created_at)
      ORDER BY work_date DESC
      LIMIT 30
    `, [branch_id]);

    // Get work type distribution
    const workTypeStats = await db.query(`
      SELECT
        COALESCE(
          NULLIF(BTRIM(oi.kategori), ''),
          NULLIF(BTRIM(i.kategori), ''),
          'Unknown'
        ) as item_type,
        SUM(COALESCE(oi.qty, 1)) as count,
        AVG(CASE
          WHEN o.status = 'completed' THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY 1
      ORDER BY count DESC
    `, [branch_id]);

    const stats = workStats.rows[0];
    const efficiency = stats.total_orders > 0 ? (stats.completed_orders / stats.total_orders * 100) : 0;
    const onTimeRate = stats.completed_orders > 0 ? (stats.completed_orders / stats.total_orders * 100) : 0;

    res.status(200).json({
      period: period,
      work_stats: {
        total_orders: parseInt(stats.total_orders) || 0,
        completed_orders: parseInt(stats.completed_orders) || 0,
        in_progress_orders: parseInt(stats.in_progress_orders) || 0,
        pending_orders: parseInt(stats.pending_orders) || 0,
        avg_duration_hours: parseFloat(stats.avg_duration_hours) || 0,
        total_work_hours: parseFloat(stats.total_work_hours) || 0,
        efficiency: Math.round(efficiency),
        on_time_rate: Math.round(onTimeRate)
      },
      material_usage: materialStats.rows,
      daily_distribution: dailyStats.rows,
      work_type_distribution: workTypeStats.rows
    });
  } catch (error) {
    console.error("Error fetching technician reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

  app.use('/api/workshop', workshopApi);

technicianApi.get("/dashboard", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }

    const hasPickupTd = await ordersHasPickupBranchColumn(db);
    const brScopeTd = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupTd);

    // Statistik order service/custom yang terlihat di cabang bengkel (termasuk kiriman toko lewat pickup_branch_id).
    const statsResult = await db.query(`
      SELECT
        COUNT(CASE WHEN o.status::text IN ('in_workshop', 'repairing', 'polishing', 'custom_work', 'sent-to-workshop') THEN 1 END) as pending_work_orders,
        COUNT(CASE WHEN o.status::text IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_work_orders,
        COUNT(CASE WHEN o.status::text IN ('completed', 'delivered', 'done_workshop', 'ready_for_pickup') THEN 1 END) as completed_work_orders
      FROM orders o
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND DATE(o.created_at) = CURRENT_DATE
    `, [branchId]);

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

  app.use('/api/technician', technicianApi);

// Get workshop orders for admin workshop — daftar default = antrian kerja tukang (sama /api/workshop/work-queue).
// scope=all (default): semua order terlihat di cabang bengkel; cross_branch / local = sempitkan by cabang asal.
app.get('/workshop-orders', async (req, res) => {
  try {
    const { branch_id, status, scope: scopeRaw } = req.query;
    const scope = String(scopeRaw ?? 'all')
      .trim()
      .toLowerCase();
    if (!['all', 'cross_branch', 'local'].includes(scope)) {
      return res.status(400).json({ error: 'scope harus all, cross_branch, atau local' });
    }

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const hasPickupWo = await ordersHasPickupBranchColumn(db);
    const brScopeWo = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWo);
    const postWorkshopStatuses = `(
          'done_workshop',
          'ready_for_pickup'
        )`;
    let branchCompareSql = '';
    if (scope === 'local') {
      branchCompareSql = 'AND o.branch_id::bigint = $1::bigint';
    } else if (scope === 'cross_branch') {
      branchCompareSql = 'AND o.branch_id::bigint <> $1::bigint';
    }

    let query = `
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.status,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.qty, 1) as quantity,
        COALESCE(oi.weight, i.weight, 0) as weight,
        COALESCE(oi.jenis, i.material) as material
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE ${brScopeWo}
        ${branchCompareSql}
        AND o.order_type::text IN ('service', 'custom')
    `;

    let params = [branch_id];
    let conditions = [];
    let orderCompletedView = false;

    if (status && status !== 'all') {
      if (status === 'pending') {
        conditions.push(`o.status::text IN ('sent-to-workshop', 'in_workshop')`);
      } else if (status === 'in_progress') {
        conditions.push(`o.status::text IN ('repairing', 'polishing', 'custom_work')`);
      } else if (status === 'completed') {
        orderCompletedView = true;
        conditions.push(`o.status::text IN ${postWorkshopStatuses}`);
      } else {
        conditions.push(`o.status::text = $${params.length + 1}`);
        params.push(status);
      }
    } else {
      conditions.push(sqlWorkshopTukangQueueStatuses('o'));
    }

    if (conditions.length > 0) {
      query += ' AND ' + conditions.join(' AND ');
    }

    query += orderCompletedView
      ? ' ORDER BY o.updated_at DESC, o.created_at DESC'
      : ' ORDER BY o.created_at ASC';

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name ?? '—',
      phone: row.phone ?? '',
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1),
      weight: parseFloat(row.weight || 0),
      material: row.material
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching workshop orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Update status order workshop (service/custom) by admin_workshop/admin_toko/tukang
app.put('/workshop-orders/:id/status', async (req, res) => {
  try {
    const orderId = parseInt(req.params.id, 10);
    const nextStatusRaw = (req.body?.status ?? '').toString().trim().toLowerCase();
    const branchId = parseInt(String(req.body?.branch_id ?? req.query?.branch_id ?? ''), 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'admin_workshop',
      'tukang',
      'stockist',
    ]);
    if (!allowedRoles.has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan update status workshop' });
    }

    const hasPickupPut = await ordersHasPickupBranchColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupPut ? ', pickup_branch_id' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupPut)) {
      return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
    }
    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({ error: 'Hanya order service/custom untuk workflow workshop' });
    }
    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();

    const allowedByRole = {
      admin_toko: new Set(['awaiting_warehouse', 'ready_for_pickup']),
      stockist: new Set(['sent-to-workshop']),
      admin_workshop: new Set([
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'custom_work',
        'cancelled',
      ]),
      tukang: new Set([
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'custom_work',
        'cancelled',
      ]),
      superadmin: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
    };
    const roleAllowedSet = allowedByRole[role] ?? new Set();
    if (!roleAllowedSet.has(nextStatusRaw)) {
      return res.status(400).json({
        error: `Status "${nextStatusRaw}" tidak diizinkan untuk role ${role}`,
      });
    }

    // Guard transitions: toko → awaiting_warehouse → (gudang) sent-to-workshop → workshop …
    const validTransitions = {
      pending: new Set(['awaiting_warehouse']),
      confirmed: new Set(['awaiting_warehouse']),
      awaiting_warehouse: new Set(['sent-to-workshop']),
      'sent-to-workshop': new Set(['in_workshop']),
      in_workshop: new Set(['repairing', 'polishing', 'done_workshop']),
      repairing: new Set(['polishing', 'done_workshop']),
      polishing: new Set(['done_workshop']),
      custom_work: new Set(['done_workshop']),
      'done_workshop': new Set(['ready_for_pickup']),
      'ready_for_pickup': new Set(['completed']),
    };
    if (nextStatusRaw === 'cancelled') {
      const mayCancel =
        (role === 'tukang' || role === 'admin_workshop' || role === 'superadmin') &&
        new Set([
          'pending',
          'confirmed',
          'awaiting_warehouse',
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work',
        ]).has(currentStatus);
      if (!mayCancel) {
        return res.status(400).json({
          error: `Pembatalan tidak diizinkan dari status "${currentStatus}"`,
        });
      }
    } else if (
      validTransitions[currentStatus] &&
      !validTransitions[currentStatus].has(nextStatusRaw) &&
      currentStatus !== nextStatusRaw
    ) {
      return res.status(400).json({
        error: `Transisi status tidak valid (${currentStatus} -> ${nextStatusRaw})`,
      });
    }

    await db.query(
      `
        UPDATE orders
        SET status = $1, updated_at = NOW()
        WHERE order_id = $2
      `,
      [nextStatusRaw, orderId]
    );
    return res.status(200).json({
      success: true,
      order_id: String(orderId),
      old_status: currentStatus,
      new_status: nextStatusRaw,
    });
  } catch (error) {
    console.error('Error updating workshop order status:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Get technicians for admin workshop
app.get('/technicians', async (req, res) => {
  try {
    const { branch_id } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const result = await db.query(`
      SELECT
        u.user_id,
        u.username,
        u.status,
        u.created_at,
        u.updated_at,
        ubr.role,
        COUNT(o.order_id) as active_orders,
        COUNT(CASE WHEN o.status IN ('completed', 'delivered') THEN 1 END) as completed_orders_today
      FROM users u
      JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      LEFT JOIN orders o ON o.user_id = u.user_id
        AND o.branch_id = ubr.branch_id
        AND DATE(o.updated_at) = CURRENT_DATE
        AND o.status IN ('in_workshop', 'repairing', 'polishing', 'custom_work')
      WHERE ubr.branch_id = $1
        AND ubr.role = 'tukang'
        AND u.status = 'active'
      GROUP BY u.user_id, u.username, u.status, u.created_at, u.updated_at, ubr.role
      ORDER BY u.username
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      user_id: row.user_id.toString(),
      username: row.username,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      role: row.role,
      active_orders: parseInt(row.active_orders || 0),
      completed_orders_today: parseInt(row.completed_orders_today || 0)
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching technicians:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

}

module.exports = { registerWorkshopRoutes };
