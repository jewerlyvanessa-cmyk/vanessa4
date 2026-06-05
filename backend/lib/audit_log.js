'use strict';

let _tableReady = false;

async function ensureAuditLogTable(db) {
  if (_tableReady) return true;
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS audit_log (
        audit_id BIGSERIAL PRIMARY KEY,
        user_id INTEGER,
        branch_id INTEGER,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload JSONB,
        ip_address TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_audit_log_created_at
      ON audit_log (created_at DESC)
    `);
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_audit_log_entity
      ON audit_log (entity_type, entity_id)
    `);
    _tableReady = true;
    return true;
  } catch (e) {
    console.warn('[audit_log] table unavailable:', e.message);
    return false;
  }
}

function clientIp(req) {
  const forwarded = req?.headers?.['x-forwarded-for'];
  if (forwarded) {
    return String(forwarded).split(',')[0].trim();
  }
  return req?.socket?.remoteAddress ?? null;
}

/**
 * Catat aksi audit (best-effort — tidak menggagalkan transaksi utama).
 */
async function writeAuditLog(db, req, entry) {
  const ok = await ensureAuditLogTable(db);
  if (!ok) return;

  const userIdRaw = req?.user?.user_id ?? req?.user?.id ?? entry.userId;
  const userId = parseInt(String(userIdRaw ?? ''), 10);
  const branchId = parseInt(String(entry.branchId ?? req?.user?.branch_id ?? ''), 10);

  const payload =
    entry.payload != null && typeof entry.payload === 'object'
      ? entry.payload
      : {};

  try {
    await db.query(
      `
        INSERT INTO audit_log (
          user_id, branch_id, action, entity_type, entity_id, payload, ip_address
        )
        VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)
      `,
      [
        Number.isFinite(userId) && userId > 0 ? userId : null,
        Number.isFinite(branchId) && branchId > 0 ? branchId : null,
        String(entry.action ?? 'unknown'),
        String(entry.entityType ?? 'unknown'),
        entry.entityId != null ? String(entry.entityId) : null,
        JSON.stringify(payload),
        clientIp(req),
      ],
    );
  } catch (e) {
    console.warn('[audit_log] write failed:', e.message);
  }
}

module.exports = {
  ensureAuditLogTable,
  writeAuditLog,
};
