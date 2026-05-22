'use strict';

function roundUpToNearest5000(amount) {
  const n = typeof amount === 'number' ? amount : parseFloat(amount);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.ceil(n / 5000) * 5000;
}

let _cachedItemsPhotoColumn = null;
async function getItemsPhotoColumn(client) {
  if (_cachedItemsPhotoColumn !== null) return _cachedItemsPhotoColumn;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name IN ('photo_produk', 'photo_url')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    if (cols.has('photo_produk')) {
      _cachedItemsPhotoColumn = 'photo_produk';
    } else if (cols.has('photo_url')) {
      _cachedItemsPhotoColumn = 'photo_url';
    } else {
      _cachedItemsPhotoColumn = null;
    }
  } catch (_) {
    _cachedItemsPhotoColumn = null;
  }
  return _cachedItemsPhotoColumn;
}

let _cachedOrderItemsPhotoColumn = null;
async function getOrderItemsPhotoColumn(client) {
  if (_cachedOrderItemsPhotoColumn !== null) return _cachedOrderItemsPhotoColumn;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'order_items'
          AND column_name IN ('photo_produk', 'photo_url')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    if (cols.has('photo_produk')) {
      _cachedOrderItemsPhotoColumn = 'photo_produk';
    } else if (cols.has('photo_url')) {
      _cachedOrderItemsPhotoColumn = 'photo_url';
    } else {
      _cachedOrderItemsPhotoColumn = null;
    }
  } catch (_) {
    _cachedOrderItemsPhotoColumn = null;
  }
  return _cachedOrderItemsPhotoColumn;
}

let _cachedItemConditionsColumns = null;
async function getItemConditionsColumns(client) {
  if (_cachedItemConditionsColumns !== null) return _cachedItemConditionsColumns;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'item_conditions'
      `,
      []
    );
    _cachedItemConditionsColumns = new Set(r.rows.map((x) => x.column_name));
  } catch (_) {
    _cachedItemConditionsColumns = new Set();
  }
  return _cachedItemConditionsColumns;
}

let _cachedOrdersJumlahColumnMode = null;
async function getOrdersJumlahColumnMode(client) {
  if (_cachedOrdersJumlahColumnMode !== null) return _cachedOrdersJumlahColumnMode;
  try {
    const r = await client.query(
      `
        SELECT is_generated
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'jumlah'
        LIMIT 1
      `,
      []
    );
    if (r.rows.length === 0) {
      _cachedOrdersJumlahColumnMode = 'missing';
    } else {
      _cachedOrdersJumlahColumnMode =
        r.rows[0].is_generated === 'ALWAYS' ? 'generated' : 'plain';
    }
  } catch (_) {
    _cachedOrdersJumlahColumnMode = 'plain';
  }
  return _cachedOrdersJumlahColumnMode;
}

module.exports = {
  roundUpToNearest5000,
  getItemsPhotoColumn,
  getOrderItemsPhotoColumn,
  getItemConditionsColumns,
  getOrdersJumlahColumnMode,
};
