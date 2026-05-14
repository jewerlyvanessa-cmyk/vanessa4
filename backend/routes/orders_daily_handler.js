const db = require('../db');
const { assertUserCanAccessBranchForOrders } = require('./order_branch_scope');
const {
  getOrderItemsPkColumn,
  orderItemLineAmountSql,
} = require('./order_items_sql');
const { ORDER_CALENDAR_TIMEZONE } = require('../lib/business_timezone');

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

function nullItemPad() {
  return {
    order_item_id: null,
    nama_item: null,
    kode_produk: null,
    weight: null,
    qty: null,
    harga_per_gram: null,
    item_total: null,
    material: null,
    purity: null,
    kategori: null,
    jenis: null,
    tipe: null,
    item_id: null,
    item_name: null,
    item_kode: null,
    item_material: null,
    item_purity: null,
    item_weight: null,
    item_kategori: null,
    item_jenis: null,
    item_tipe: null,
    photo_produk: null,
  };
}

/**
 * Gabungkan baris order (tanpa item) + baris item → bentuk flat sama seperti JOIN lama
 * (satu baris per baris order_item; order tanpa item → satu baris dengan kolom item NULL).
 */
function mergeOrdersAndItemsFlat(orderRows, itemRows) {
  const byOrder = new Map();
  for (const it of itemRows) {
    const oid = it.order_id;
    if (!byOrder.has(oid)) byOrder.set(oid, []);
    byOrder.get(oid).push(it);
  }
  const out = [];
  for (const o of orderRows) {
    const oid = o.order_id;
    const list = byOrder.get(oid) || [];
    if (list.length === 0) {
      out.push({ ...o, ...nullItemPad() });
      continue;
    }
    for (const it of list) {
      out.push({ ...o, ...it });
    }
  }
  return out;
}

/**
 * GET /orders/daily (relatif ke mount /api → /api/orders/daily) dan GET /orders/daily di server.js.
 *
 * Cabang:
 * - Order dengan o.branch_id = cabang (aktivitas hari itu: dibuat atau ada pembayaran completed).
 * - Jika kolom payments.revenue_branch_id ada: juga order dari cabang lain yang punya pembayaran
 *   completed pada tanggal itu dengan atribusi pendapatan ke cabang ini (pelunasan di cabang pickup).
 *
 * Performa: default dua query (order + item) agar tidak mem-bloat hash join. Fallback satu query:
 *   ?legacy_join=1
 */
/**
 * @returns {Promise<{ ok: true, rows: any[] } | { ok: false, status: number, body: object }>}
 */
async function fetchOrdersDailyPayload(req) {
  const { branch_id, date } = req.query;

  if (!branch_id) {
    return { ok: false, status: 400, body: { error: 'branch_id is required' } };
  }

  const scope = await assertUserCanAccessBranchForOrders(req, branch_id);
  if (!scope.ok) {
    return { ok: false, status: scope.status, body: scope.body };
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
          OR o.order_id IN (
            SELECT p.order_id
            FROM payments p
            WHERE p.status = 'completed'
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
          OR o.order_id IN (
            SELECT p.order_id
            FROM payments p
            WHERE p.status = 'completed'
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

  const useLegacyJoin =
    String(req.query.legacy_join || '')
      .trim()
      .toLowerCase() === '1' ||
    String(req.query.legacy_join || '')
      .trim()
      .toLowerCase() === 'true';

  if (useLegacyJoin) {
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
    const legacyParams = [...params];
    if (filterUid != null) {
      query += ` AND o.user_id = $2`;
      legacyParams.push(filterUid);
    }
    if (targetDate) {
      legacyParams.push(targetDate);
    }
    query += ' ORDER BY o.created_at DESC';
    const result = await db.query(query, legacyParams);
    return { ok: true, rows: result.rows };
  }

  let ordersSql = `
        SELECT
          o.*,
          c.name as customer_name,
          c.phone as customer_phone,
          c.address as customer_address
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        WHERE ${branchActivityWhere}
      `;
  const ordersParams = [...params];
  if (filterUid != null) {
    ordersSql += ` AND o.user_id = $2`;
    ordersParams.push(filterUid);
  }
  if (targetDate) {
    ordersParams.push(targetDate);
  }
  ordersSql += ' ORDER BY o.created_at DESC';

  const [ordersRes, pk] = await Promise.all([
    db.query(ordersSql, ordersParams),
    getOrderItemsPkColumn(),
  ]);
  const orderRows = ordersRes.rows;
  if (orderRows.length === 0) {
    return { ok: true, rows: [] };
  }

  const orderIds = orderRows.map((r) => r.order_id).filter((id) => id != null);
  if (!/^(order_item_id|id)$/.test(String(pk))) {
    return {
      ok: false,
      status: 500,
      body: { error: 'Invalid order_items PK column' },
    };
  }

  const itemsSql = `
        SELECT
          oi.order_id,
          oi.${pk} AS order_item_id,
          oi.nama_item,
          oi.kode_produk,
          oi.weight,
          oi.qty,
          oi.harga_per_gram,
          ${lineSql} as item_total,
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
          i.tipe as item_tipe,
          oi.photo_produk
        FROM order_items oi
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE oi.order_id = ANY($1::bigint[])
        ORDER BY oi.order_id, oi.${pk}
      `;
  const itemsRes = await db.query(itemsSql, [orderIds]);
  const flat = mergeOrdersAndItemsFlat(orderRows, itemsRes.rows);
  return { ok: true, rows: flat };
}

async function getOrdersDaily(req, res) {
  try {
    const r = await fetchOrdersDailyPayload(req);
    if (!r.ok) {
      return res.status(r.status).json(r.body);
    }
    return res.status(200).json(r.rows);
  } catch (error) {
    console.error('Error fetching daily orders:', error);
    res.status(500).json({
      error: 'Internal server error',
      detail: error && error.message ? String(error.message) : undefined,
    });
  }
}

getOrdersDaily.fetchOrdersDailyPayload = fetchOrdersDailyPayload;

module.exports = getOrdersDaily;
