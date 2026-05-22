/**
 * Introspeksi kolom opsional tabel `items` (DB baru vs lama).
 */

let _cachedItemsCreatedByExists = null;

async function itemsHasCreatedByColumn(db) {
  if (_cachedItemsCreatedByExists !== null) return _cachedItemsCreatedByExists;
  try {
    const r = await db.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name = 'created_by'
        LIMIT 1
      `,
      []
    );
    _cachedItemsCreatedByExists = r.rows.length > 0;
  } catch (_) {
    _cachedItemsCreatedByExists = false;
  }
  return _cachedItemsCreatedByExists;
}

async function getItemsColumnFlags(client) {
  const r = await client.query(
    `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'items'
        AND column_name IN ('ownership', 'stock_type', 'is_quick_registered')
    `,
    []
  );
  const cols = new Set(r.rows.map((x) => x.column_name));
  return {
    ownership: cols.has('ownership'),
    stockType: cols.has('stock_type'),
    isQuickRegistered: cols.has('is_quick_registered'),
  };
}

function itemSelectStockFields(flags) {
  const parts = [];
  if (flags.ownership) parts.push('ownership');
  if (flags.stockType) parts.push('stock_type');
  return parts.length ? `, ${parts.join(', ')}` : '';
}

async function updateItemStatusAndStock(
  client,
  flags,
  { itemId, status, ownership, stockType }
) {
  if (flags.ownership && flags.stockType) {
    await client.query(
      `UPDATE items SET status = $1, ownership = $2, stock_type = $3, updated_at = NOW()
       WHERE item_id = $4`,
      [status, ownership, stockType, itemId]
    );
    return;
  }
  await client.query(
    `UPDATE items SET status = $1, updated_at = NOW() WHERE item_id = $2`,
    [status, itemId]
  );
}

/** Stok masuk buyback setelah pembayaran kasir (payments_core). */
async function incrementBuybackItemStock(client, flags, itemId, qtyVal) {
  if (flags.ownership && flags.stockType) {
    return client.query(
      `
        UPDATE items
        SET quantity = COALESCE(quantity, 0) + $1,
            status = 'buyback',
            ownership = 'toko',
            stock_type = 'inventory',
            updated_at = NOW()
        WHERE item_id = $2
        RETURNING COALESCE(quantity, 0) AS quantity
      `,
      [qtyVal, itemId]
    );
  }
  return client.query(
    `
      UPDATE items
      SET quantity = COALESCE(quantity, 0) + $1,
          status = 'buyback',
          updated_at = NOW()
      WHERE item_id = $2
      RETURNING COALESCE(quantity, 0) AS quantity
    `,
    [qtyVal, itemId]
  );
}

function defaultItemsPhotoColumnName(detected) {
  return detected || 'photo_produk';
}

async function insertManualOrderItem(
  client,
  flags,
  itemsPhotoColName,
  {
    nama_item,
    kode_produk,
    weight,
    material,
    purity,
    kategori,
    jenis,
    tipe,
    ownership,
    stock_type,
    status,
    is_quick_registered,
    branch_id,
    initialItemQty,
    photo_produk,
  }
) {
  const cols = [
    'name',
    'kode_produk',
    'weight',
    'material',
    'purity',
    'kategori',
    'jenis',
    'tipe',
  ];
  const vals = [
    nama_item,
    kode_produk,
    weight,
    material,
    purity,
    kategori,
    jenis,
    tipe,
  ];

  if (flags.ownership) {
    cols.push('ownership');
    vals.push(ownership || 'unknown');
  }
  if (flags.stockType) {
    cols.push('stock_type');
    vals.push(stock_type || 'non_inventory');
  }

  cols.push('status');
  vals.push(status || 'unregistered');

  if (flags.isQuickRegistered) {
    cols.push('is_quick_registered');
    vals.push(is_quick_registered || false);
  }

  cols.push('branch_id', 'source', 'quantity', itemsPhotoColName);
  vals.push(branch_id, 'manual', initialItemQty, photo_produk);

  const placeholders = vals.map((_, i) => `$${i + 1}`).join(', ');
  const sql = `INSERT INTO items (${cols.join(', ')}) VALUES (${placeholders}) RETURNING item_id`;
  const itemResult = await client.query(sql, vals);
  return itemResult.rows[0].item_id;
}

function formatDbErrorForClient(error) {
  if (!error) return 'Unknown error';
  if (error.code === '25P02') {
    return (
      'Transaksi database terputus (perintah SQL sebelumnya gagal). ' +
      'Jalankan di PostgreSQL: backend/sql/patch_vanessa3_production_complete.sql, ' +
      'lalu restart API. Cek log PM2 untuk baris Error creating order di atas pesan ini.'
    );
  }
  if (error.code === '42883') {
    return (
      'Fungsi generate_nota_order belum ada di database. ' +
      'Jalankan backend/sql/patch_generate_nota_order.sql lalu restart API.'
    );
  }
  if (error.code === '428C9' || /generated column/i.test(String(error.message))) {
    return (
      'Kolom jumlah di database dihitung otomatis (GENERATED). ' +
      'Deploy ulang server.js terbaru lalu restart API (pm2 restart vanessa).'
    );
  }
  return error.detail || error.message || String(error);
}

module.exports = {
  itemsHasCreatedByColumn,
  getItemsColumnFlags,
  itemSelectStockFields,
  updateItemStatusAndStock,
  incrementBuybackItemStock,
  insertManualOrderItem,
  formatDbErrorForClient,
  defaultItemsPhotoColumnName,
};
