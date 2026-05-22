'use strict';

/** Cache hasil introspection kolom `transfers` (proses hidup). */
const _columnExistsCache = new Map();

async function transfersHasColumn(db, columnName) {
  if (_columnExistsCache.has(columnName)) {
    return _columnExistsCache.get(columnName);
  }
  try {
    const r = await db.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'transfers'
          AND column_name = $1
        LIMIT 1
      `,
      [columnName]
    );
    const exists = r.rows.length > 0;
    _columnExistsCache.set(columnName, exists);
    return exists;
  } catch (_) {
    _columnExistsCache.set(columnName, false);
    return false;
  }
}

/** Kolom opsional untuk SELECT/INSERT transfer (source_type, courier). */
async function getTransfersOptionalColumns(db) {
  const [hasSourceTypeCol, hasCourierCol] = await Promise.all([
    transfersHasColumn(db, 'source_type'),
    transfersHasColumn(db, 'courier'),
  ]);
  return { hasSourceTypeCol, hasCourierCol };
}

module.exports = {
  transfersHasColumn,
  getTransfersOptionalColumns,
};
