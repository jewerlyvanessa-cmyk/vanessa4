'use strict';

/**
 * Cache introspection kolom/tabel orders + SQL scope bengkel (dipakai server & routes/workshop).
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
 * Cabang tempat order service/custom dikerjakan (bengkel), bukan pickup pelanggan.
 * Diset di metadata saat gudang/bengkel terima (`sent-to-workshop`).
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
 * Order terlihat di cabang bengkel: cabang order, cabang pickup, atau metadata `service_workshop_branch_id`.
 * `pickup_branch_id` = tempat ambil pelanggan setelah selesai; jangan dipakai sebagai cabang kerja bengkel.
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
 * Visibilitas order di cabang bengkel — **sumber kebenaran = SQL** (sama dengan GET /workshop-orders & work-queue).
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
 * walau `orders.branch_id` sudah di bengkel.
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
  if (!(await paymentsHasRevenueBranchColumn(pool))) {
    return false;
  }
  const r = await pool.query(
    `
      SELECT 1
      FROM orders o
      WHERE o.order_id = $2
        AND EXISTS (
          SELECT 1
          FROM payments p
          WHERE p.order_id = o.order_id
            AND p.status::text = 'completed'
            AND COALESCE(p.revenue_branch_id, o.branch_id) = $1::bigint
        )
      LIMIT 1
    `,
    [bid, oid]
  );
  return r.rows.length > 0;
}

/** Sama dengan GET /api/workshop/work-queue — antrian aktif tukang (belum selesai bengkel). */
function sqlWorkshopTukangQueueStatuses(alias) {
  return `${alias}.status::text IN (
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work'
        )`;
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
  ordersSupportsWorkshopStatuses,
  ordersEstimateColumns,
  orderCostBreakdownsTableExists,
  ensureOrderCostBreakdownsSchema,
  ordersHasPickupBranchColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  orderVisibleAtWorkshopBranchId,
  orderVisibleAtWorkshopBranchSql,
  paymentsHasRevenueBranchColumn,
  orderVisibleForWorkshopStatusPut,
  workshopMetadataBranchId,
  sqlWorkshopTukangQueueStatuses,
  jsonSafeDbRow,
};
