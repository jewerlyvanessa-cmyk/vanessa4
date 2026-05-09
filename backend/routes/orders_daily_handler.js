const db = require('../db');
const { assertUserCanAccessBranchForOrders } = require('./order_branch_scope');
const { orderItemLineAmountSql } = require('./order_items_sql');

const ORDER_CALENDAR_TIMEZONE =
  /^[\w/-]+$/.test(String(process.env.BUSINESS_TIMEZONE || '').trim())
    ? String(process.env.BUSINESS_TIMEZONE).trim()
    : 'Asia/Jakarta';

/** @type {boolean | null} */
let _cachedPaymentsRevenueBranchColumn = null;

async function paymentsHasRevenueBranchColumn() {
  if (_cachedPaymentsRevenueBranchColumn !== null) {
    return _cachedPaymentsRevenueBranchColumn;
  }
  try {
    const r = await db.query(
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
 * Scope harian:
 * - CS: hanya order yang dibuat user itu (user_id dari JWT) untuk branch yang diminta.
 * - Role lain: seluruh order untuk branch yang diminta.
 */
function dailyOrdersUserFilterFromJwt(req) {
  const role = (req.user?.role ?? '').toString().trim().toLowerCase();
  if (role !== 'cs') return null;
  const uid = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
  if (!Number.isFinite(uid) || uid <= 0) return null;
  return uid;
}

/**
 * GET /orders/daily (relatif ke mount /api → /api/orders/daily) dan GET /orders/daily di server.js.
 *
 * Cabang:
 * - Order dengan o.branch_id = cabang (aktivitas hari itu: dibuat atau ada pembayaran completed).
 * - Jika kolom payments.revenue_branch_id ada: juga order dari cabang lain yang punya pembayaran
 *   completed pada tanggal itu dengan atribusi pendapatan ke cabang ini (pelunasan di cabang pickup).
 */
async function getOrdersDaily(req, res) {
  try {
    const { branch_id, date } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const scope = await assertUserCanAccessBranchForOrders(req, branch_id);
    if (!scope.ok) {
      return res.status(scope.status).json(scope.body);
    }
    const bid = scope.branchId;

    const targetDate =
      date && String(date).trim().length > 0 ? String(date).trim() : null;

    const filterUid = dailyOrdersUserFilterFromJwt(req);
    const params = [bid];

    const lineSql = orderItemLineAmountSql('oi');

    const createdDateMatch = (paramRef) => `
        (
          o.created_at::date = ${paramRef}::date
          OR (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at AT TIME ZONE 'UTC'))::date = ${paramRef}::date
        )
      `;

    const paymentDateMatch = (alias, paramRef) => `
        (
          (timezone('${ORDER_CALENDAR_TIMEZONE}', ${alias}.created_at))::date = ${paramRef}::date
          OR (timezone('${ORDER_CALENDAR_TIMEZONE}', ${alias}.created_at AT TIME ZONE 'UTC'))::date = ${paramRef}::date
          OR ${alias}.created_at::date = ${paramRef}::date
        )
      `;

    const hasRevBranch = await paymentsHasRevenueBranchColumn();
    const nowDateRef = `(timezone('${ORDER_CALENDAR_TIMEZONE}', now()))`;

    let branchActivityWhere;
    if (targetDate) {
      const dateRef = filterUid != null ? '$3' : '$2';
      const activitySql = `(
          ${createdDateMatch(dateRef)}
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND ${paymentDateMatch('p', dateRef)}
          )
        )`;
      const crossBranchSql = hasRevBranch
        ? `EXISTS (
            SELECT 1
            FROM payments p_rev
            WHERE p_rev.order_id = o.order_id
              AND p_rev.status = 'completed'
              AND ${paymentDateMatch('p_rev', dateRef)}
              AND COALESCE(p_rev.revenue_branch_id, o.branch_id) = $1
          )`
        : 'FALSE';
      branchActivityWhere = `((o.branch_id = $1 AND ${activitySql}) OR ${crossBranchSql})`;
    } else {
      const activitySql = `(
          ${createdDateMatch(nowDateRef)}
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND ${paymentDateMatch('p', nowDateRef)}
          )
        )`;
      const crossBranchSql = hasRevBranch
        ? `EXISTS (
            SELECT 1
            FROM payments p_rev
            WHERE p_rev.order_id = o.order_id
              AND p_rev.status = 'completed'
              AND ${paymentDateMatch('p_rev', nowDateRef)}
              AND COALESCE(p_rev.revenue_branch_id, o.branch_id) = $1
          )`
        : 'FALSE';
      branchActivityWhere = `((o.branch_id = $1 AND ${activitySql}) OR ${crossBranchSql})`;
    }

    let query = `
        SELECT
          o.*,
          c.name as customer_name,
          c.phone as customer_phone,
          c.address as customer_address,
          oi.nama_item,
          oi.kode_produk,
          oi.weight,
          oi.qty,
          oi.harga_per_gram,
          ${lineSql} as item_total,
          -- Source of truth for material/kadar on order lines: order_items
          oi.material as material,
          oi.purity as purity,
          oi.kategori,
          oi.jenis,
          oi.tipe,
          i.item_id,
          i.name as item_name,
          i.kode_produk as item_kode,
          i.material as item_material,
          i.purity as item_purity,
          i.weight as item_weight,
          i.kategori as item_kategori,
          i.jenis as item_jenis,
          i.tipe as item_tipe
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE ${branchActivityWhere}
      `;

    if (filterUid != null) {
      query += ` AND o.user_id = $2`;
      params.push(filterUid);
    }

    if (targetDate) {
      params.push(targetDate);
    }

    query += ' ORDER BY o.created_at DESC';

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching daily orders:', error);
    res.status(500).json({
      error: 'Internal server error',
      detail: error && error.message ? String(error.message) : undefined,
    });
  }
}

module.exports = getOrdersDaily;
