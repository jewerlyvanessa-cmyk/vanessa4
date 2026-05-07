const db = require('../db');

let _pkCol = null;

/**
 * PK order_items di DB bisa `order_item_id` (migrasi baru) atau `id` (lama).
 */
async function getOrderItemsPkColumn() {
  if (_pkCol) return _pkCol;
  const r = await db.query(
    `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'order_items'
        AND column_name IN ('order_item_id', 'id')
      ORDER BY CASE WHEN column_name = 'order_item_id' THEN 0 ELSE 1 END
      LIMIT 1
    `,
  );
  _pkCol = r.rows[0]?.column_name || 'order_item_id';
  return _pkCol;
}

/**
 * Nilai baris order_items tanpa kolom `jumlah` / `total` (skema berbeda antar migrasi).
 */
function orderItemLineAmountSql(alias = 'oi') {
  return `(COALESCE(${alias}.qty, 1)::numeric * COALESCE(${alias}.weight, 0) * COALESCE(${alias}.harga_per_gram, 0))`;
}

module.exports = { getOrderItemsPkColumn, orderItemLineAmountSql };
