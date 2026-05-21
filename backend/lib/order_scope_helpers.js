'use strict';

/**
 * Aturan scope harian (orders + payments) per role:
 * - CS: hanya order/pembayaran untuk order yang dibuat user itu.
 * - Kasir: pembayaran yang divalidasi user itu (+ legacy NULL jika validated_by_only).
 * - Admin toko / manajer / superadmin: seluruh cabang (manajer/superadmin lintas cabang via branch scope).
 */

function normalizeRole(req) {
  return (req.user?.role ?? '').toString().trim().toLowerCase();
}

/**
 * CS: order hari ini / harian hanya milik user login.
 * Utamakan user_id dari query (UI), fallback JWT.
 */
function resolveCsOrderUserFilterFromReq(req) {
  if (normalizeRole(req) !== 'cs') return null;

  const fromQuery = parseInt(String(req.query.user_id ?? ''), 10);
  const fromJwt = parseInt(
    String(req.user?.user_id ?? req.user?.id ?? ''),
    10
  );
  const uid =
    Number.isFinite(fromQuery) && fromQuery > 0
      ? fromQuery
      : Number.isFinite(fromJwt) && fromJwt > 0
        ? fromJwt
        : null;
  return uid;
}

function resolvePaymentActorUserId(req) {
  const fromQuery = parseInt(String(req.query.user_id ?? ''), 10);
  const fromJwt = parseInt(
    String(req.user?.user_id ?? req.user?.id ?? ''),
    10
  );
  if (Number.isFinite(fromQuery) && fromQuery > 0) return fromQuery;
  if (Number.isFinite(fromJwt) && fromJwt > 0) return fromJwt;
  return null;
}

function parseValidatedByOnlyQuery(req) {
  const role = normalizeRole(req);
  const raw = (req.query.validated_by_only ?? '').toString().trim().toLowerCase();
  const off = raw === '0' || raw === 'false' || raw === 'no';
  const on = raw === '1' || raw === 'true' || raw === 'yes';
  if (on) return true;
  if (off) return false;
  // Hanya filter validated_by jika klien meminta eksplisit (validated_by_only=1).
  return false;
}

/**
 * @param {import('express').Request} req
 * @param {{ hasValidatedByCol: boolean }} opts
 * @returns {{ mode: 'none' } | { mode: 'cs_orders', userId: number } | { mode: 'kasir_validated', userId: number, includeLegacyNull: boolean }}
 */
function resolvePaymentsUserFilterMode(req, { hasValidatedByCol }) {
  const csUid = resolveCsOrderUserFilterFromReq(req);
  if (csUid != null) {
    return { mode: 'cs_orders', userId: csUid };
  }

  const validatedOnly = parseValidatedByOnlyQuery(req);
  if (validatedOnly) {
    if (!hasValidatedByCol) {
      return { mode: 'none' };
    }
    const uid = resolvePaymentActorUserId(req);
    if (uid != null) {
      return {
        mode: 'kasir_validated',
        userId: uid,
        includeLegacyNull: true,
      };
    }
    return { mode: 'none' };
  }

  const userIdFilterRaw = (req.query.user_id ?? '').toString().trim();
  if (userIdFilterRaw.length > 0 && hasValidatedByCol) {
    const uid = parseInt(userIdFilterRaw, 10);
    if (Number.isFinite(uid) && uid > 0) {
      return {
        mode: 'kasir_validated',
        userId: uid,
        includeLegacyNull: false,
      };
    }
  }

  return { mode: 'none' };
}

/**
 * @param {{ mode: string, userId?: number, includeLegacyNull?: boolean }} filter
 * @param {number} paramIndex placeholder index (1-based)
 */
function paymentsUserFilterSql(filter, paramIndex) {
  if (filter.mode === 'cs_orders') {
    return ` AND o.user_id::bigint = $${paramIndex}::bigint`;
  }
  if (filter.mode === 'kasir_validated') {
    if (filter.includeLegacyNull) {
      return ` AND (p.validated_by::bigint = $${paramIndex}::bigint OR p.validated_by IS NULL)`;
    }
    return ` AND p.validated_by::bigint = $${paramIndex}::bigint`;
  }
  return '';
}

/**
 * Tambahkan param user filter ke array params; kembalikan SQL tambahan.
 * @param {any[]} params
 * @param {{ mode: string, userId?: number, includeLegacyNull?: boolean }} filter
 */
function appendPaymentsUserFilter(params, filter) {
  const sql = paymentsUserFilterSql(filter, params.length + 1);
  if (filter.mode === 'cs_orders' || filter.mode === 'kasir_validated') {
    params.push(filter.userId);
  }
  return sql;
}

module.exports = {
  resolveCsOrderUserFilterFromReq,
  resolvePaymentActorUserId,
  parseValidatedByOnlyQuery,
  resolvePaymentsUserFilterMode,
  paymentsUserFilterSql,
  appendPaymentsUserFilter,
};
