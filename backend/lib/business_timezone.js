'use strict';

/**
 * Zona waktu operasional bisnis: **WIB = UTC+7 (GMT+7)**.
 * Default IANA `Asia/Jakarta` (tanpa DST). Disamakan dengan filter tanggal di PostgreSQL (`timezone(...)`).
 *
 * Override opsional: env `BUSINESS_TIMEZONE` — harus nama IANA valid (huruf, angka, `_`, `/`, `-`).
 */
const RAW = String(process.env.BUSINESS_TIMEZONE || '').trim();
const ORDER_CALENDAR_TIMEZONE = /^[\w/-]+$/.test(RAW) ? RAW : 'Asia/Jakarta';

module.exports = {
  ORDER_CALENDAR_TIMEZONE,
  /** Untuk teks log / UI (Indonesia barat). */
  BUSINESS_TIMEZONE_OFFSET_LABEL: 'GMT+7 (WIB)',
};
