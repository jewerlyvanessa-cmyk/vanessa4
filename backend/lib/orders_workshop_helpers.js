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
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'metadata'
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
 * Order service/custom untuk cabang bengkel: cabang order ATAU cabang pengambilan (kiriman dari toko).
 */
function sqlOrdersVisibleAtWorkshopBranch(alias, paramIndex, hasPickupCol) {
  if (hasPickupCol) {
    return `(${alias}.branch_id = $${paramIndex}::bigint OR ${alias}.pickup_branch_id = $${paramIndex}::bigint)`;
  }
  return `${alias}.branch_id = $${paramIndex}::bigint`;
}

function orderVisibleAtWorkshopBranchId(orderRow, workshopBranchId, hasPickupCol) {
  const wid = parseInt(String(workshopBranchId ?? ''), 10);
  if (!Number.isFinite(wid) || wid <= 0) return false;
  const ob = parseInt(String(orderRow.branch_id ?? ''), 10);
  if (Number.isFinite(ob) && ob === wid) return true;
  if (!hasPickupCol) return false;
  const p = orderRow.pickup_branch_id;
  if (p == null) return false;
  const pb = parseInt(String(p), 10);
  return Number.isFinite(pb) && pb === wid;
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
  ordersHasPickupBranchColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  orderVisibleAtWorkshopBranchId,
  sqlWorkshopTukangQueueStatuses,
  jsonSafeDbRow,
};
