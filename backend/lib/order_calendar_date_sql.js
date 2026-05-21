'use strict';

const { ORDER_CALENDAR_TIMEZONE } = require('./business_timezone');

/**
 * Cocokkan timestamp order/payment ke tanggal kalender bisnis (WIB).
 *
 * Kolom `TIMESTAMP` (tanpa zona) di DB Vanessa = jam dinding toko WIB
 * (koneksi pool harus `SET TIME ZONE 'Asia/Jakarta'`).
 * Kolom `TIMESTAMPTZ` tetap dikonversi ke kalender WIB.
 */
function timestampOnBusinessDateSql(columnExpr, paramRef) {
  const col = columnExpr || 'o.created_at';
  const tz = ORDER_CALENDAR_TIMEZONE;
  // TIMESTAMP tanpa zona (orders.created_at): jam dinding WIB — jangan pakai timezone(col) langsung.
  // TIMESTAMPTZ: konversi ke kalender WIB.
  return `(
    (${col})::date = ${paramRef}::date
    OR (((${col}) AT TIME ZONE '${tz}')::timestamptz AT TIME ZONE '${tz}')::date = ${paramRef}::date
    OR (timezone('${tz}', (${col})::timestamptz))::date = ${paramRef}::date
  )`;
}

function timestampOnBusinessDateBetweenSql(columnExpr, fromRef, toRef) {
  const col = columnExpr || 'o.created_at';
  const tz = ORDER_CALENDAR_TIMEZONE;
  return `(
    (${col})::date BETWEEN ${fromRef}::date AND ${toRef}::date
    OR (((${col}) AT TIME ZONE '${tz}')::timestamptz AT TIME ZONE '${tz}')::date BETWEEN ${fromRef}::date AND ${toRef}::date
    OR (timezone('${tz}', (${col})::timestamptz))::date BETWEEN ${fromRef}::date AND ${toRef}::date
  )`;
}

/** Filter tanggal aktivitas pembayaran (created_at + payment_date jika kolom ada). */
function paymentActivityDateSql(alias, paramRef, hasPaymentDateCol) {
  const p = alias || 'p';
  const parts = [timestampOnBusinessDateSql(`${p}.created_at`, paramRef)];
  if (hasPaymentDateCol) {
    parts.push(
      `(${p}.payment_date IS NOT NULL AND ${timestampOnBusinessDateSql(`${p}.payment_date`, paramRef)})`
    );
  }
  return `(${parts.join(' OR ')})`;
}

function paymentActivityDateBetweenSql(alias, fromRef, toRef, hasPaymentDateCol) {
  const p = alias || 'p';
  const parts = [timestampOnBusinessDateBetweenSql(`${p}.created_at`, fromRef, toRef)];
  if (hasPaymentDateCol) {
    parts.push(
      `(${p}.payment_date IS NOT NULL AND ${timestampOnBusinessDateBetweenSql(`${p}.payment_date`, fromRef, toRef)})`
    );
  }
  return `(${parts.join(' OR ')})`;
}

module.exports = {
  timestampOnBusinessDateSql,
  timestampOnBusinessDateBetweenSql,
  paymentActivityDateSql,
  paymentActivityDateBetweenSql,
  ORDER_CALENDAR_TIMEZONE,
};
