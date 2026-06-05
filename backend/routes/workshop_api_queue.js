'use strict';

const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopOrderAssignedToTechnician,
  jsonSafeDbRow,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopQueueRoutes(workshopApi, { db }) {
workshopApi.get("/work-queue", async (req, res) => {
  try {
    const branchId = req.query.branch_id;
    const technicianIdRaw = req.query.technician_id;
    const technicianId = parseInt(String(technicianIdRaw ?? ''), 10);
    const unassignedOnlyRaw = String(req.query.unassigned_only ?? '')
      .trim()
      .toLowerCase();
    const unassignedOnly =
      unassignedOnlyRaw === '1' ||
      unassignedOnlyRaw === 'true' ||
      unassignedOnlyRaw === 'yes';

    if (!branchId) {
      return res.status(400).json({ error: "branch_id is required" });
    }

    const hasPickupWq = await ordersHasPickupBranchColumn(db);
    const hasMetaWq = await ordersHasMetadataColumn(db);
    const brScopeWq = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWq, hasMetaWq);
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

    if (unassignedOnly) {
      inner += ` AND (${sqlWorkshopOrderIsUnassigned('o', hasMetaWq)})`;
    }

    // Dengan technician_id: filter "pekerjaan milik teknisi ini" (halaman Update Progress).
    // Jika kolom metadata ada, penugasan workshop = hanya metadata (assigned_*), BUKAN orders.user_id
    // (user_id sering pembuat order/kasir — menyebabkan order muncul di Update Progress padahal belum Mulai).
    // Tanpa kolom metadata: legacy memakai orders.user_id sebagai teknisi.
    if (Number.isFinite(technicianId) && technicianId > 0) {
      if (hasMetaWq) {
        inner += ` AND (${sqlWorkshopOrderAssignedToTechnician('o', 2, hasMetaWq)})`;
        params.push(technicianId);
      } else {
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
    // Verifikasi deploy: di DevTools → Network → response headers, atau curl -I.
    res.setHeader('X-Vanessa-WorkQueue-Rules', '2026-05-11-v3');
    res.status(200).json(rows);
  } catch (error) {
    console.error("Error fetching work queue:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

/** Cek apakah proses Node ini benar-benar pakai logika workshop terbaru + introspeksi DB. */
workshopApi.get('/work-queue-diagnostics', async (req, res) => {
  try {
    const hasMeta = await ordersHasMetadataColumn(db);
    res.setHeader('X-Vanessa-WorkQueue-Rules', '2026-05-11-v3');
    return res.status(200).json({
      rules_version: '2026-05-11-v3',
      orders_table_has_metadata_column: hasMeta,
      unassigned_mode: hasMeta
        ? 'metadata_positive_id_only_no_user_id_gate'
        : 'legacy_user_id_null_means_unassigned',
      technician_id_filter: hasMeta
        ? 'metadata_assigned_fields_only'
        : 'orders_user_id_equals_technician',
      note:
        'Jika orders_table_has_metadata_column false padahal kolom ada, restart Node; ' +
        'jika true tapi antrian kosong, cek branch_id & visibilitas order di cabang workshop.',
    });
  } catch (e) {
    console.error('work-queue-diagnostics:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Service/custom menunggu kirim gudang → workshop (`awaiting_warehouse`).
workshopApi.get('/warehouse-service-queue', async (req, res) => {
  try {
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (!new Set(['admin_warehouse', 'superadmin', 'manajer', 'stockist']).has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan' });
    }
    const hasPickupWq = await ordersHasPickupBranchColumn(db);
    const result = await db.query(
      `
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.branch_id,
          ${hasPickupWq ? 'o.pickup_branch_id,' : ''}
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          b.name AS store_branch_name,
          COALESCE(oi.nama_item, i.name) AS item_name
        FROM orders o
        JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN branches b ON b.branch_id = o.branch_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.order_type::text IN ('service', 'custom')
          AND o.status::text = 'awaiting_warehouse'
        ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
      `
    );
    const processedRows = result.rows.map((row) => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      branch_id: row.branch_id != null ? String(row.branch_id) : null,
      pickup_branch_id:
        hasPickupWq && row.pickup_branch_id != null
          ? String(row.pickup_branch_id)
          : null,
      store_branch_name: row.store_branch_name,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
    }));
    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching warehouse service queue:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Service/custom: menunggu persetujuan admin workshop (bukan gudang) sebelum masuk antrian pekerjaan.
workshopApi.get('/service-incoming', async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (!new Set(['admin_workshop', 'superadmin', 'manajer']).has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan' });
    }
    const hasPickupSi = await ordersHasPickupBranchColumn(db);
    const hasMetaSi = await ordersHasMetadataColumn(db);
    const brScopeSi = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupSi, hasMetaSi);
    const unassignedIncoming =
      hasPickupSi
        ? `(
            o.pickup_branch_id IS NULL
            OR o.pickup_branch_id = o.branch_id
          )
          AND o.branch_id IS DISTINCT FROM $1::bigint`
        : 'FALSE';
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
          AND (
            ${brScopeSi}
            OR (${unassignedIncoming})
          )
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

}

module.exports = { registerWorkshopQueueRoutes };
