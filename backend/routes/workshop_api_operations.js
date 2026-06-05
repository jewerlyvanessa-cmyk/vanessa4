'use strict';

const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  orderVisibleForWorkshopStatusPut,
  sqlWorkshopOrderAssignedToTechnician,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopOperationsRoutes(workshopApi, { db, broadcastWorkshop }) {
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
    // Mulai kerja + bind teknisi hanya tukang (break-glass: superadmin/manajer).
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'tukang',
      'manajer',
    ]);
    if (!allowedRoles.has(role)) {
      return res
        .status(403)
        .json({ error: 'Role tidak diizinkan update progress workshop' });
    }

    const hasPickupProgress = await ordersHasPickupBranchColumn(db);
    const hasMetaProgress = await ordersHasMetadataColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupProgress ? ', pickup_branch_id' : ''}
          ${hasMetaProgress ? ', metadata' : ''}
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
    const visibleProgress = await orderVisibleForWorkshopStatusPut(
      db,
      orderId,
      branchId,
      hasPickupProgress,
      hasMetaProgress,
    );
    if (!visibleProgress) {
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
      manajer: new Set([
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
      // Tukang "Mulai" langsung ke repairing/custom_work; admin bisa ke in_workshop dulu.
      'sent-to-workshop': new Set(['in_workshop', 'repairing', 'custom_work']),
      in_workshop: new Set(['repairing', 'polishing', 'custom_work', 'done_workshop']),
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

    const techIdParsed = parseInt(String(technician_id ?? ''), 10);
    const techId = Number.isFinite(techIdParsed) && techIdParsed > 0 ? techIdParsed : null;
    const isTukang = role === 'tukang';
    const metaPatch = {
      last_updated_by: technician_id,
      last_update_notes: notes,
      updated_at: new Date().toISOString(),
    };
    // When a technician starts/updating, bind assignment so the order moves from "Antrian kerja"
    // to "Update progress" for that technician.
    if (isTukang && techId != null) {
      metaPatch.assigned_technician_id = String(techId);
    }

    if (hasMetaProgress) {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
          WHERE order_id = $3
        `,
        [nextStatus, JSON.stringify(metaPatch), orderId],
      );
    } else {
      // Legacy DB without metadata: use orders.user_id to keep assignment working.
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              user_id = COALESCE(user_id, $2::bigint)
          WHERE order_id = $3
        `,
        [nextStatus, techId, orderId],
      );
    }

    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      broadcastWorkshop(
        `Order #${orderId} sedang dikerjakan tukang (${nextStatus})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: { order_id: orderId, status: nextStatus, technician_id: techId },
        }
      );
    }
    if (nextStatus === 'done_workshop' && currentStatus !== 'done_workshop') {
      broadcastWorkshop(
        `Order #${orderId} selesai di tukang — siap kirim ke toko`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_done_tukang',
          payload: { order_id: orderId, status: 'done_workshop' },
        }
      );
    }

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
    const branchId = (req.query.branch_id ?? '').toString().trim();
    const periodRaw = (req.query.period ?? 'today').toString().trim().toLowerCase();
    const period = ['today', 'week', 'month', 'quarter'].includes(periodRaw)
      ? periodRaw
      : 'today';
    const technicianId = parseInt(String(req.query.technician_id ?? ''), 10);
    const sessionUserId = parseInt(
      String(req.user?.user_id ?? req.user?.id ?? ''),
      10,
    );
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();

    if (!branchId) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }
    if (!Number.isFinite(technicianId) || technicianId <= 0) {
      return res.status(400).json({ error: 'technician_id wajib diisi' });
    }
    if (role === 'tukang' && sessionUserId !== technicianId) {
      return res.status(403).json({
        error: 'Tidak boleh melihat laporan tukang lain',
      });
    }

    const hasMeta = await ordersHasMetadataColumn(db);
    const techFilter = hasMeta
      ? sqlWorkshopOrderAssignedToTechnician('o', 2, hasMeta)
      : 'o.user_id::bigint = $2::bigint';
    const params = [branchId, technicianId];

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = 'AND DATE(o.created_at) = CURRENT_DATE';
    } else if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    } else if (period === 'quarter') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    }

    const doneStatuses =
      "('done_workshop', 'ready_for_pickup', 'completed')";
    const inProgressStatuses =
      "('in_workshop', 'repairing', 'polishing', 'custom_work')";
    const pendingStatuses = "('sent-to-workshop')";

    const baseWhere = `
      WHERE o.branch_id::bigint = $1::bigint
        AND o.order_type::text IN ('service', 'custom')
        AND (${techFilter})
        ${dateFilter}
    `;

    const workStats = await db.query(
      `
      SELECT
        COUNT(*) as total_orders,
        COUNT(CASE WHEN o.status::text IN ${doneStatuses} THEN 1 END) as completed_orders,
        COUNT(CASE WHEN o.status::text IN ${inProgressStatuses} THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN o.status::text IN ${pendingStatuses} THEN 1 END) as pending_orders,
        AVG(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration_hours,
        SUM(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as total_work_hours
      FROM orders o
      ${baseWhere}
    `,
      params,
    );

    const materialStats = await db.query(
      `
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
      ${baseWhere}
        AND o.status::text IN ${doneStatuses}
      GROUP BY 1
      ORDER BY total_weight_used DESC
    `,
      params,
    );

    const dailyStats = await db.query(
      `
      SELECT
        DATE(o.created_at) as work_date,
        COUNT(*) as orders_count,
        COUNT(CASE WHEN o.status::text IN ${doneStatuses} THEN 1 END) as completed_count
      FROM orders o
      ${baseWhere}
      GROUP BY DATE(o.created_at)
      ORDER BY work_date DESC
      LIMIT 30
    `,
      params,
    );

    const workTypeStats = await db.query(
      `
      SELECT
        COALESCE(
          NULLIF(BTRIM(oi.kategori), ''),
          NULLIF(BTRIM(i.kategori), ''),
          'Unknown'
        ) as item_type,
        SUM(COALESCE(oi.qty, 1)) as count,
        AVG(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      ${baseWhere}
      GROUP BY 1
      ORDER BY count DESC
    `,
      params,
    );

    const stats = workStats.rows[0] ?? {};
    const totalOrders = parseInt(stats.total_orders, 10) || 0;
    const completedOrders = parseInt(stats.completed_orders, 10) || 0;
    const efficiency =
      totalOrders > 0 ? (completedOrders / totalOrders) * 100 : 0;
    const onTimeRate = efficiency;

    res.setHeader('X-Vanessa-Technician-Reports', '2026-05-17-v1');
    res.status(200).json({
      period,
      technician_id: String(technicianId),
      work_stats: {
        total_orders: totalOrders,
        completed_orders: completedOrders,
        in_progress_orders: parseInt(stats.in_progress_orders, 10) || 0,
        pending_orders: parseInt(stats.pending_orders, 10) || 0,
        avg_duration_hours: parseFloat(stats.avg_duration_hours) || 0,
        total_work_hours: parseFloat(stats.total_work_hours) || 0,
        efficiency: Math.round(efficiency),
        on_time_rate: Math.round(onTimeRate),
      },
      material_usage: materialStats.rows,
      daily_distribution: dailyStats.rows,
      work_type_distribution: workTypeStats.rows,
    });
  } catch (error) {
    console.error("Error fetching technician reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});
}

module.exports = { registerWorkshopOperationsRoutes };
