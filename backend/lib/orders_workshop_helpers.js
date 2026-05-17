'use strict';

/**
 * Cache introspection kolom/tabel orders + SQL scope workshop (dipakai server & routes/workshop).
 */

let _cachedOrdersMetadataColumnExists = null; // boolean | null (unknown)
async function ordersHasMetadataColumn(client) {
  if (_cachedOrdersMetadataColumnExists !== null) {
    return _cachedOrdersMetadataColumnExists;
  }
  try {
    // Jangan kunci ke public saja — beberapa deploy pakai search_path/schema lain.
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'orders'
          AND column_name = 'metadata'
          AND table_schema NOT IN ('pg_catalog', 'information_schema')
        LIMIT 1
      `,
      []
    );
    _cachedOrdersMetadataColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedOrdersMetadataColumnExists = false;
  }
  return _cachedOrdersMetadataColumnExists;
}

/** Deteksi kolom metadata langsung di DB (hindari cache salah setelah migrasi tanpa restart). */
async function ordersHasMetadataColumnLive(client) {
  try {
    await client.query('SELECT metadata FROM orders WHERE false LIMIT 0');
    _cachedOrdersMetadataColumnExists = true;
    return true;
  } catch (e) {
    if (e && e.code === '42703') {
      _cachedOrdersMetadataColumnExists = false;
      return false;
    }
    return ordersHasMetadataColumn(client);
  }
}

let _cachedOrdersSupportsWorkshopStatuses = null; // boolean | null (unknown)
async function ordersSupportsWorkshopStatuses(client) {
  if (_cachedOrdersSupportsWorkshopStatuses !== null) {
    return _cachedOrdersSupportsWorkshopStatuses;
  }
  try {
    const r = await client.query(
      `
        SELECT pg_get_constraintdef(c.oid) AS def
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'public'
          AND t.relname = 'orders'
          AND c.conname = 'orders_status_check'
        LIMIT 1
      `,
      []
    );
    const def = (r.rows?.[0]?.def ?? '').toString().toLowerCase();
    _cachedOrdersSupportsWorkshopStatuses =
      def.includes('sent-to-workshop') ||
      def.includes('in_workshop') ||
      def.includes('ready_for_pickup');
  } catch (_) {
    _cachedOrdersSupportsWorkshopStatuses = false;
  }
  return _cachedOrdersSupportsWorkshopStatuses;
}

let _cachedOrdersEstimateColumns = null; // { estimate_amount, estimate_due_at, estimate_duration_text, estimate_notes }
async function ordersEstimateColumns(client) {
  if (_cachedOrdersEstimateColumns !== null) {
    return _cachedOrdersEstimateColumns;
  }
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name IN (
            'estimate_amount',
            'estimate_due_at',
            'estimate_duration_text',
            'estimate_notes'
          )
      `,
      []
    );
    const set = new Set((r.rows ?? []).map((row) => String(row.column_name)));
    _cachedOrdersEstimateColumns = {
      estimate_amount: set.has('estimate_amount'),
      estimate_due_at: set.has('estimate_due_at'),
      estimate_duration_text: set.has('estimate_duration_text'),
      estimate_notes: set.has('estimate_notes'),
    };
  } catch (_) {
    _cachedOrdersEstimateColumns = {
      estimate_amount: false,
      estimate_due_at: false,
      estimate_duration_text: false,
      estimate_notes: false,
    };
  }
  return _cachedOrdersEstimateColumns;
}

let _cachedOrderCostBreakdownsTableExists = null; // boolean | null (unknown)
async function orderCostBreakdownsTableExists(client) {
  if (_cachedOrderCostBreakdownsTableExists !== null) {
    return _cachedOrderCostBreakdownsTableExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'order_cost_breakdowns'
        LIMIT 1
      `,
      []
    );
    _cachedOrderCostBreakdownsTableExists = r.rows.length > 0;
  } catch (_) {
    _cachedOrderCostBreakdownsTableExists = false;
  }
  return _cachedOrderCostBreakdownsTableExists;
}

/**
 * Menjamin tabel `order_cost_breakdowns` + kolom estimasi di `orders` ada (idempoten).
 * Dipanggil saat simpan biaya bila migrasi belum dijalankan di server.
 */
async function ensureOrderCostBreakdownsSchema(pool) {
  if (_cachedOrderCostBreakdownsTableExists === true) {
    return;
  }
  const has = await orderCostBreakdownsTableExists(pool);
  if (has) {
    return;
  }
  try {
    await pool.query(`
      ALTER TABLE IF EXISTS orders
        ADD COLUMN IF NOT EXISTS estimate_amount NUMERIC(14, 2),
        ADD COLUMN IF NOT EXISTS estimate_due_at TIMESTAMPTZ,
        ADD COLUMN IF NOT EXISTS estimate_duration_text TEXT,
        ADD COLUMN IF NOT EXISTS estimate_notes TEXT;
    `);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS order_cost_breakdowns (
        breakdown_id BIGSERIAL PRIMARY KEY,
        order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
        revision INTEGER NOT NULL,
        material_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
        labor_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
        other_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
        notes TEXT,
        created_by BIGINT REFERENCES users(user_id),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT order_cost_breakdowns_revision_unique UNIQUE (order_id, revision),
        CONSTRAINT order_cost_breakdowns_non_negative_costs CHECK (
          material_cost >= 0 AND labor_cost >= 0 AND other_cost >= 0
        )
      );
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_order_cost_breakdowns_order_created_at
        ON order_cost_breakdowns(order_id, created_at DESC);
    `);
    _cachedOrderCostBreakdownsTableExists = true;
    _cachedOrdersEstimateColumns = null;
  } catch (err) {
    console.error('ensureOrderCostBreakdownsSchema failed:', err);
    throw err;
  }
}

let _cachedOrdersPickupBranchColumnExists = null;
async function ordersHasPickupBranchColumn(client) {
  if (_cachedOrdersPickupBranchColumnExists !== null) {
    return _cachedOrdersPickupBranchColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'pickup_branch_id'
        LIMIT 1
      `,
      []
    );
    _cachedOrdersPickupBranchColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedOrdersPickupBranchColumnExists = false;
  }
  return _cachedOrdersPickupBranchColumnExists;
}

/**
 * Cabang tempat order service/custom dikerjakan (workshop), bukan pickup pelanggan.
 * Diset di metadata saat gudang/workshop terima (`sent-to-workshop`).
 */
function workshopMetadataBranchId(orderRow) {
  const m = orderRow?.metadata;
  if (m == null) return null;
  const obj =
    typeof m === 'string'
      ? (() => {
          try {
            return JSON.parse(m);
          } catch {
            return null;
          }
        })()
      : m;
  if (!obj || typeof obj !== 'object') return null;
  const v = obj.service_workshop_branch_id ?? obj.serviceWorkshopBranchId;
  if (v == null || String(v).trim() === '') return null;
  const id = parseInt(String(v).trim(), 10);
  return Number.isFinite(id) && id > 0 ? id : null;
}

/**
 * Order terlihat di cabang workshop: cabang order, cabang pickup, atau metadata `service_workshop_branch_id`.
 * `pickup_branch_id` = tempat ambil pelanggan setelah selesai; jangan dipakai sebagai cabang kerja workshop.
 */
function sqlOrdersVisibleAtWorkshopBranch(
  alias,
  paramIndex,
  hasPickupCol,
  hasMetadataCol = false
) {
  const base = hasPickupCol
    ? `(${alias}.branch_id = $${paramIndex}::bigint OR ${alias}.pickup_branch_id = $${paramIndex}::bigint)`
    : `${alias}.branch_id = $${paramIndex}::bigint`;
  if (!hasMetadataCol) return base;
  return `(${base} OR (
    COALESCE(NULLIF(BTRIM(${alias}.metadata->>'service_workshop_branch_id'), ''), '') <> ''
    AND (${alias}.metadata->>'service_workshop_branch_id')::bigint = $${paramIndex}::bigint
  ))`;
}

function orderVisibleAtWorkshopBranchId(
  orderRow,
  workshopBranchId,
  hasPickupCol,
  hasMetadataCol = false
) {
  const wid = parseInt(String(workshopBranchId ?? ''), 10);
  if (!Number.isFinite(wid) || wid <= 0) return false;
  const ob = parseInt(String(orderRow.branch_id ?? ''), 10);
  if (Number.isFinite(ob) && ob === wid) return true;
  if (!hasPickupCol) {
    if (hasMetadataCol) {
      const mb = workshopMetadataBranchId(orderRow);
      return mb != null && mb === wid;
    }
    return false;
  }
  const p = orderRow.pickup_branch_id;
  if (p != null) {
    const pb = parseInt(String(p), 10);
    if (Number.isFinite(pb) && pb === wid) return true;
  }
  if (hasMetadataCol) {
    const mb = workshopMetadataBranchId(orderRow);
    if (mb != null && mb === wid) return true;
  }
  return false;
}

/**
 * Visibilitas order di cabang workshop — **sumber kebenaran = SQL** (sama dengan GET /workshop-orders & work-queue).
 * Menghindari drift bentuk `metadata` dari node-pg vs logika parse di JS.
 */
async function orderVisibleAtWorkshopBranchSql(
  pool,
  orderId,
  workshopBranchId,
  hasPickupCol,
  hasMetadataCol
) {
  const bid = parseInt(String(workshopBranchId ?? ''), 10);
  const oid = parseInt(String(orderId ?? ''), 10);
  if (!Number.isFinite(bid) || bid <= 0 || !Number.isFinite(oid) || oid <= 0) {
    return false;
  }
  const vis = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupCol, hasMetadataCol);
  const r = await pool.query(
    `SELECT 1 FROM orders o WHERE o.order_id = $2 AND (${vis}) LIMIT 1`,
    [bid, oid]
  );
  return r.rows.length > 0;
}

let _cachedPaymentsRevenueBranchColumn = null;
async function paymentsHasRevenueBranchColumn(client) {
  if (_cachedPaymentsRevenueBranchColumn !== null) {
    return _cachedPaymentsRevenueBranchColumn;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'revenue_branch_id'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsRevenueBranchColumn = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsRevenueBranchColumn = false;
  }
  return _cachedPaymentsRevenueBranchColumn;
}

/**
 * Scope cabang untuk PUT status / update-progress workshop: sama logika dasar GET /workshop-orders,
 * plus (jika kolom ada) order yang muncul di GET /orders/daily untuk cabang lewat atribusi pendapatan
 * (`payments.revenue_branch_id`) — supaya admin toko bisa "Terima" (done_workshop → ready_for_pickup)
 * walau `orders.branch_id` sudah di workshop.
 * Jangan pakai COALESCE(revenue, o.branch_id) saat revenue null: setelah terima workshop `branch_id`
 * bisa cabang workshop sehingga admin toko salah tertaut; fallback pickup / metadata asal.
 */
async function orderVisibleForWorkshopStatusPut(
  pool,
  orderId,
  branchId,
  hasPickupCol,
  hasMetadataCol
) {
  if (
    await orderVisibleAtWorkshopBranchSql(
      pool,
      orderId,
      branchId,
      hasPickupCol,
      hasMetadataCol
    )
  ) {
    return true;
  }
  const bid = parseInt(String(branchId ?? ''), 10);
  const oid = parseInt(String(orderId ?? ''), 10);
  if (!Number.isFinite(bid) || bid <= 0 || !Number.isFinite(oid) || oid <= 0) {
    return false;
  }

  const orClauses = [];
  if (hasPickupCol) {
    orClauses.push(`o.pickup_branch_id::bigint = $1::bigint`);
  }
  if (hasMetadataCol) {
    orClauses.push(`(
      COALESCE(NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), ''), '') <> ''
      AND (o.metadata->>'service_origin_branch_id')::bigint = $1::bigint
    )`);
  }

  const hasRev = await paymentsHasRevenueBranchColumn(pool);
  if (hasRev) {
    orClauses.push(`EXISTS (
      SELECT 1
      FROM payments p
      WHERE p.order_id = o.order_id
        AND p.status::text = 'completed'
        AND (
          (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $1::bigint)
          OR (p.revenue_branch_id IS NULL AND o.branch_id::bigint = $1::bigint)
        )
    )`);
  }

  if (orClauses.length === 0) {
    return false;
  }

  const r = await pool.query(
    `
      SELECT 1
      FROM orders o
      WHERE o.order_id = $2
        AND (${orClauses.join('\n        OR ')})
      LIMIT 1
    `,
    [bid, oid]
  );
  return r.rows.length > 0;
}

/** Sama dengan GET /api/workshop/work-queue — antrian aktif tukang (belum selesai workshop). */
function sqlWorkshopTukangQueueStatuses(alias) {
  return `${alias}.status::text IN (
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work'
        )`;
}

/**
 * Ekspresi boolean SQL: order belum ditugaskan ke teknisi (selaras filter `unassigned_only` work-queue).
 * Tanpa kolom metadata: `orders.user_id` = pembuat order (CS/kasir), BUKAN tukang — anggap belum assign.
 */
function sqlWorkshopOrderIsUnassigned(alias, hasMetadataCol) {
  if (!hasMetadataCol) {
    return 'TRUE';
  }
  // Hanya assigned_technician_id (angka). Jangan pakai assigned_technician (nama user)
  // agar tidak salah dianggap sudah ditugaskan.
  return `NOT (
    COALESCE(${alias}.metadata->>'assigned_technician_id', '') ~ '^[0-9]+$'
    AND (NULLIF(BTRIM(${alias}.metadata->>'assigned_technician_id'), ''))::bigint > 0
  )`;
}

/**
 * Visibilitas antrian pekerjaan: cabang kerja workshop (branch_id setelah disetujui)
 * atau metadata.service_workshop_branch_id. Tidak memakai pickup_branch_id (bukan cabang kerja).
 */
function sqlWorkshopAntrianVisibleAtBranch(alias, paramIndex, hasMetadataCol) {
  const parts = [`${alias}.branch_id::bigint = $${paramIndex}::bigint`];
  if (hasMetadataCol) {
    parts.push(`(
      COALESCE(NULLIF(BTRIM(${alias}.metadata->>'service_workshop_branch_id'), ''), '') <> ''
      AND (${alias}.metadata->>'service_workshop_branch_id')::bigint = $${paramIndex}::bigint
    )`);
  }
  return `(${parts.join(' OR ')})`;
}

/**
 * Ekspresi boolean SQL: penugasan workshop milik teknisi `$paramIndex` (user_id).
 * Parameter query harus menyertakan `user_id` teknisi di indeks ini.
 */
function sqlWorkshopOrderAssignedToTechnician(alias, technicianParamIndex, hasMetadataCol) {
  if (!hasMetadataCol) {
    return `${alias}.user_id::bigint = $${technicianParamIndex}::bigint`;
  }
  return `(
    COALESCE(${alias}.metadata->>'assigned_technician_id', '') = $${technicianParamIndex}::text
    OR COALESCE(${alias}.metadata->>'assigned_technician', '') = $${technicianParamIndex}::text
  )`;
}

/**
 * Ekspresi boolean SQL: order workshop (service/custom) terlihat di cabang untuk PUT status
 * (sumber kebenaran selaras `orderVisibleForWorkshopStatusPut`, tanpa filter per order_id).
 */
function sqlOrderVisibleAtBranchForWorkshopPut(
  alias,
  branchParamIndex,
  hasPickupCol,
  hasMetadataCol,
  hasRevenueCol
) {
  const parts = [
    `(${sqlOrdersVisibleAtWorkshopBranch(
      alias,
      branchParamIndex,
      hasPickupCol,
      hasMetadataCol
    )})`,
  ];
  if (hasPickupCol) {
    parts.push(
      `(${alias}.pickup_branch_id::bigint = $${branchParamIndex}::bigint)`
    );
  }
  if (hasMetadataCol) {
    parts.push(`(
      COALESCE(NULLIF(BTRIM(${alias}.metadata->>'service_origin_branch_id'), ''), '') <> ''
      AND (${alias}.metadata->>'service_origin_branch_id')::bigint = $${branchParamIndex}::bigint
    )`);
  }
  if (hasRevenueCol) {
    parts.push(`EXISTS (
      SELECT 1
      FROM payments p
      WHERE p.order_id = ${alias}.order_id
        AND p.status::text = 'completed'
        AND (
          (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $${branchParamIndex}::bigint)
          OR (p.revenue_branch_id IS NULL AND ${alias}.branch_id::bigint = $${branchParamIndex}::bigint)
        )
    )`);
  }
  return `(${parts.join('\n    OR ')})`;
}

/**
 * Visibilitas daftar «siap ambil» di toko (CS Ambil): cabang toko asal / branch_id / pickup / revenue.
 */
function sqlStoreReadyForPickupListVisible(
  alias,
  branchParamIndex,
  hasPickupCol,
  hasMetadataCol,
  hasRevenueCol
) {
  const parts = [`${alias}.branch_id::bigint = $${branchParamIndex}::bigint`];
  if (hasMetadataCol) {
    parts.push(`(
      COALESCE(NULLIF(BTRIM(${alias}.metadata->>'service_origin_branch_id'), ''), '') <> ''
      AND (${alias}.metadata->>'service_origin_branch_id')::bigint = $${branchParamIndex}::bigint
    )`);
  }
  if (hasPickupCol) {
    parts.push(
      `(${alias}.pickup_branch_id::bigint = $${branchParamIndex}::bigint)`
    );
  }
  if (hasRevenueCol) {
    parts.push(`EXISTS (
      SELECT 1
      FROM payments p
      WHERE p.order_id = ${alias}.order_id
        AND p.status::text IN ('completed', 'pending')
        AND (
          (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $${branchParamIndex}::bigint)
          OR (p.revenue_branch_id IS NULL AND ${alias}.branch_id::bigint = $${branchParamIndex}::bigint)
        )
    )`);
  }
  return `(${parts.join('\n    OR ')})`;
}

/**
 * Order sudah diterima admin toko (siap tampil di CS Ambil).
 * Utama: metadata.store_receipt_confirmed_at; fallback: branch_id sudah dikembalikan ke cabang asal.
 */
function sqlStoreReceiptConfirmedForPickup(alias, branchParamIndex, hasMetadataCol) {
  if (!hasMetadataCol) {
    return 'TRUE';
  }
  return `(
    COALESCE(NULLIF(BTRIM(${alias}.metadata->>'store_receipt_confirmed_at'), ''), '') <> ''
    OR (
      ${alias}.branch_id::bigint = $${branchParamIndex}::bigint
      AND COALESCE(NULLIF(BTRIM(${alias}.metadata->>'service_origin_branch_id'), ''), '') <> ''
      AND (NULLIF(BTRIM(${alias}.metadata->>'service_origin_branch_id'), ''))::bigint = ${alias}.branch_id::bigint
    )
  )`;
}

/**
 * CS Ambil / POST pickup: sama filter dengan GET ready-for-pickup-list (cabang toko + sudah «Terima»).
 */
async function orderAllowedForStorePickup(
  pool,
  orderId,
  branchId,
  hasPickupCol,
  hasMetadataCol,
  hasRevenueCol
) {
  const bid = parseInt(String(branchId ?? ''), 10);
  const oid = parseInt(String(orderId ?? ''), 10);
  if (!Number.isFinite(bid) || bid <= 0 || !Number.isFinite(oid) || oid <= 0) {
    return false;
  }
  const vis = sqlStoreReadyForPickupListVisible(
    'o',
    1,
    hasPickupCol,
    hasMetadataCol,
    hasRevenueCol
  );
  const confirmed = sqlStoreReceiptConfirmedForPickup('o', 1, hasMetadataCol);
  const r = await pool.query(
    `
      SELECT 1
      FROM orders o
      WHERE o.order_id = $2
        AND (${vis})
        AND (${confirmed})
      LIMIT 1
    `,
    [bid, oid]
  );
  return r.rows.length > 0;
}

/** Node-pg dapat mengembalikan int8 sebagai BigInt; JSON.stringify gagal tanpa ini. */
function jsonSafeDbRow(row) {
  if (row == null || typeof row !== 'object') return row;
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    if (typeof v === 'bigint') {
      out[k] = v.toString();
    } else {
      out[k] = v;
    }
  }
  return out;
}

module.exports = {
  ordersHasMetadataColumn,
  ordersHasMetadataColumnLive,
  ordersSupportsWorkshopStatuses,
  ordersEstimateColumns,
  orderCostBreakdownsTableExists,
  ensureOrderCostBreakdownsSchema,
  ordersHasPickupBranchColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  sqlWorkshopAntrianVisibleAtBranch,
  orderVisibleAtWorkshopBranchId,
  orderVisibleAtWorkshopBranchSql,
  paymentsHasRevenueBranchColumn,
  orderVisibleForWorkshopStatusPut,
  workshopMetadataBranchId,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopOrderAssignedToTechnician,
  sqlOrderVisibleAtBranchForWorkshopPut,
  sqlStoreReadyForPickupListVisible,
  sqlStoreReceiptConfirmedForPickup,
  orderAllowedForStorePickup,
  jsonSafeDbRow,
};
