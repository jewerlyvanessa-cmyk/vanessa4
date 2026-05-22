const db = require('../db');

/**
 * Pastikan user JWT boleh mengakses branch_id untuk agregasi order (hari ini / harian).
 * Superadmin: bebas. Lainnya: harus punya baris di user_branch_roles.
 */
async function assertUserCanAccessBranchForOrders(req, branchIdRaw) {
  const queryBid = parseInt(String(branchIdRaw ?? '').trim(), 10);
  const jwtBid = parseInt(String(req.user?.branch_id ?? '').trim(), 10);
  const bid =
    Number.isFinite(queryBid) && queryBid > 0
      ? queryBid
      : Number.isFinite(jwtBid) && jwtBid > 0
        ? jwtBid
        : NaN;
  if (!Number.isFinite(bid) || bid <= 0) {
    return { ok: false, status: 400, body: { error: 'branch_id wajib dan harus angka valid' } };
  }

  const role = (req.user?.role || '').toString().trim().toLowerCase();
  // Owner / manajer / superadmin: laporan lintas cabang (read-only agregasi).
  if (role === 'superadmin' || role === 'manajer' || role === 'owner') {
    return { ok: true, branchId: bid };
  }

  const uid = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false, status: 403, body: { error: 'Unauthorized' } };
  }

  try {
    const r = await db.query(
      `
        SELECT 1
        FROM user_branch_roles
        WHERE user_id = $1 AND branch_id = $2
        LIMIT 1
      `,
      [uid, bid]
    );
    // Admin toko / CS / kasir: izinkan cabang dari query jika ada di user_branch_roles
    // (UI bisa ganti cabang sebelum JWT di-refresh lewat switch-context).
    if (r.rows.length === 0) {
      return {
        ok: false,
        status: 403,
        body: { error: 'Cabang tidak diizinkan untuk akun ini' },
      };
    }
  } catch (e) {
    console.error('assertUserCanAccessBranchForOrders:', e);
    return { ok: false, status: 500, body: { error: 'Internal server error' } };
  }

  return { ok: true, branchId: bid };
}

module.exports = { assertUserCanAccessBranchForOrders };
