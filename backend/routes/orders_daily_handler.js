const db = require('../db');
const { assertUserCanAccessBranchForOrders } = require('./order_branch_scope');
const { orderItemLineAmountSql } = require('./order_items_sql');

const ORDER_CALENDAR_TIMEZONE =
  /^[\w/-]+$/.test(String(process.env.BUSINESS_TIMEZONE || '').trim())
    ? String(process.env.BUSINESS_TIMEZONE).trim()
    : 'Asia/Jakarta';

/** Hanya CS yang filter order harian ke user sendiri; role lain seluruh cabang (abaikan query user_id). */
function dailyOrdersUserFilterFromJwt(req) {
  const role = (req.user?.role || '').toString().trim().toLowerCase();
  const uid = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
  if (role === 'cs' && Number.isFinite(uid) && uid > 0) {
    return uid;
  }
  return null;
}

/**
 * GET /orders/daily (relatif ke mount /api → /api/orders/daily) dan GET /orders/daily di server.js.
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
        WHERE o.branch_id = $1
      `;
    if (filterUid != null) {
      query += ` AND o.user_id = $2`;
      params.push(filterUid);
    }

    if (targetDate) {
      query += `
        AND (
          (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at))::date = $${params.length + 1}::date
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at))::date = $${params.length + 1}::date
          )
        )
      `;
      params.push(targetDate);
    } else {
      query += `
        AND (
          (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at))::date = (timezone('${ORDER_CALENDAR_TIMEZONE}', now()))::date
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at))::date = (timezone('${ORDER_CALENDAR_TIMEZONE}', now()))::date
          )
        )
      `;
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
