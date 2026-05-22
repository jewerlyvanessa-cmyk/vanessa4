'use strict';

const { assertUserCanAccessBranchForOrders } = require('../routes/order_branch_scope');
const {
  paymentsHasValidatedByColumn,
  paymentsHasRevenueBranchColumn,
  paymentsHasPaymentDateColumn,
} = require('./payments_schema_helpers');
const {
  paymentActivityDateSql,
} = require('./order_calendar_date_sql');
const { ORDER_CALENDAR_TIMEZONE } = require('./business_timezone');
const {
  resolvePaymentsUserFilterMode,
  appendPaymentsUserFilter,
} = require('./order_scope_helpers');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function todayYmdWib() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: ORDER_CALENDAR_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

function parseBranchIdsParam(raw) {
  if (raw == null || String(raw).trim() === '') return [];
  return String(raw)
    .split(',')
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => Number.isFinite(n) && n > 0);
}

/**
 * @param {import('express').Request} req
 * @param {import('pg').Pool | { query: Function }} db
 */
async function resolveOwnerDashboardBranchIds(req, db) {
  const role = String(req.user?.role ?? '')
    .trim()
    .toLowerCase();
  if (!['owner', 'manajer', 'superadmin'].includes(role)) {
    return { ok: false, status: 403, body: { error: 'Forbidden' } };
  }

  const fromQuery = parseBranchIdsParam(req.query.branch_ids);
  if (fromQuery.length > 0) {
    const allowed = [];
    for (const bid of fromQuery) {
      const scope = await assertUserCanAccessBranchForOrders(req, bid);
      if (scope.ok) allowed.push(scope.branchId);
    }
    return { ok: true, branchIds: [...new Set(allowed)] };
  }

  const uid = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false, status: 401, body: { error: 'Unauthorized' } };
  }

  const r = await db.query(
    `
      SELECT DISTINCT branch_id
      FROM user_branch_roles
      WHERE user_id = $1
      ORDER BY branch_id
    `,
    [uid]
  );
  const branchIds = r.rows
    .map((row) => parseInt(String(row.branch_id), 10))
    .filter((n) => Number.isFinite(n) && n > 0);

  return { ok: true, branchIds };
}

/**
 * Agregat stok ready seluruh cabang (satu query).
 */
async function fetchOwnerStockTotals(db, branchIds) {
  if (!branchIds.length) {
    return { ready_qty: 0, ready_sku: 0 };
  }
  const r = await db.query(
    `
      SELECT
        COALESCE(SUM(COALESCE(i.quantity, 0)), 0)::bigint AS ready_qty,
        COUNT(*)::int AS ready_sku
      FROM items i
      WHERE i.branch_id = ANY($1::bigint[])
        AND LOWER(TRIM(COALESCE(i.status, ''))) = 'ready'
        AND COALESCE(i.quantity, 0) > 0
    `,
    [branchIds]
  );
  const row = r.rows[0] || {};
  return {
    ready_qty: parseInt(row.ready_qty ?? 0, 10) || 0,
    ready_sku: parseInt(row.ready_sku ?? 0, 10) || 0,
  };
}

/**
 * Ringkasan pembayaran harian (tanpa daftar transaksi — ringan).
 */
async function fetchOwnerPaymentSummary(db, req, branchId, dateYmd) {
  const hasPaymentDateCol = await paymentsHasPaymentDateColumn(db);
  const hasValidatedByCol = await paymentsHasValidatedByColumn(db);
  const hasRevBranchCol = await paymentsHasRevenueBranchColumn(db);

  const paymentDateSql = paymentActivityDateSql('p', '$2', hasPaymentDateCol);
  const branchScopeSql = hasRevBranchCol
    ? `(o.branch_id::bigint = $1::bigint OR (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $1::bigint))`
    : `o.branch_id::bigint = $1::bigint`;

  const userFilter = resolvePaymentsUserFilterMode(req, {
    hasValidatedByCol,
  });

  const params = [branchId, dateYmd];
  let extraWhere = '';
  if (
    userFilter.mode !== 'none' &&
    (userFilter.mode !== 'kasir_validated' || hasValidatedByCol)
  ) {
    extraWhere += appendPaymentsUserFilter(params, userFilter);
  }

  const r = await db.query(
    `
      SELECT
        COUNT(*)::int AS total_payments,
        COALESCE(SUM(p.amount), 0)::float AS total_amount,
        COALESCE(SUM(CASE
          WHEN LOWER(TRIM(COALESCE(o.order_type::text, ''))) IN ('jual', 'service', 'custom')
            THEN p.amount ELSE 0 END), 0)::float AS income_amount,
        COALESCE(SUM(CASE
          WHEN LOWER(TRIM(COALESCE(o.order_type::text, ''))) = 'buyback'
            THEN p.amount ELSE 0 END), 0)::float AS expense_amount,
        COUNT(*) FILTER (
          WHERE LOWER(TRIM(COALESCE(o.order_type::text, ''))) = 'buyback'
        )::int AS buyback_payments,
        COUNT(*) FILTER (
          WHERE LOWER(TRIM(COALESCE(o.order_type::text, ''))) IN ('jual', 'service', 'custom')
        )::int AS income_payments
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      WHERE ${branchScopeSql}
        AND ${paymentDateSql}
        AND p.status = 'completed'
        ${extraWhere}
    `,
    params
  );

  const row = r.rows[0] || {};
  return {
    total_payments: parseInt(row.total_payments ?? 0, 10) || 0,
    total_amount: parseFloat(row.total_amount ?? 0) || 0,
    income_amount: parseFloat(row.income_amount ?? 0) || 0,
    expense_amount: parseFloat(row.expense_amount ?? 0) || 0,
    buyback_payments: parseInt(row.buyback_payments ?? 0, 10) || 0,
    income_payments: parseInt(row.income_payments ?? 0, 10) || 0,
  };
}

module.exports = {
  DATE_RE,
  todayYmdWib,
  parseBranchIdsParam,
  resolveOwnerDashboardBranchIds,
  fetchOwnerStockTotals,
  fetchOwnerPaymentSummary,
};
