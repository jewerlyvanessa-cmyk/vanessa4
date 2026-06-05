-- Jejak audit untuk aksi sensitif (stok, pembayaran, opname).
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
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_branch ON audit_log (branch_id, created_at DESC);
