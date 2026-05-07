const db = require('../db');

/**
 * Pastikan user JWT boleh mengakses branch_id untuk agregasi order (hari ini / harian).
 * Superadmin: bebas. Lainnya: harus punya baris di user_branch_roles.
 */
async function assertUserCanAccessBranchForOrders(req, branchIdRaw) {
  const bid = parseInt(String(branchIdRaw ?? '').trim(), 10);
  if (!Number.isFinite(bid) || bid <= 0) {
    return { ok: false, status: 400, body: { error: 'branch_id wajib dan harus angka valid' } };
  }

  const role = (req.user?.role || '').toString().trim().toLowerCase();
  if (role === 'superadmin') {
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
