'use strict';

/**
 * Stockist clients send item_name as a display label "KODE - Nama" while
 * `items.name` in DB is usually just "Nama" (kode is in kode_produk). Extract
 * the code so we can match the source row when the label !== items.name.
 */
function parseKodeProdukFromTransferItemLabel(itemLabel) {
  const t = String(itemLabel ?? '').trim();
  if (!t) return null;
  const m = t.match(/^(.+?)\s*[-\u2013\u2014]\s+(.+)$/u);
  if (m) return m[1].trim();
  const idx = t.indexOf(' - ');
  if (idx > 0) return t.slice(0, idx).trim();
  return null;
}

/**
 * If DB has no `transfers.courier` column, POST may prefix notes with
 * "Kurir: …" — expose that as `courier` in GET for clients.
 */
function extractKurirFromTransferNotes(notes) {
  if (notes == null) return null;
  const s = String(notes);
  const m = s.match(/^\s*Kurir:\s*([^\n\r]+)/m);
  return m ? m[1].trim() : null;
}

function extractTransferSourceTypeFromNotes(notes) {
  if (notes == null) return null;
  const s = String(notes);
  const m = s.match(/^\s*Sumber asli:\s*([^\n\r]+)/im);
  return m ? m[1].trim().toLowerCase() : null;
}

module.exports = {
  parseKodeProdukFromTransferItemLabel,
  extractKurirFromTransferNotes,
  extractTransferSourceTypeFromNotes,
};
