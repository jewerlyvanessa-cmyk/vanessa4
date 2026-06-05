-- Idempotency untuk POST sensitif (payments, orders) — cegah double submit saat sync offline.
CREATE TABLE IF NOT EXISTS api_idempotency (
  idempotency_key TEXT PRIMARY KEY,
  method TEXT NOT NULL DEFAULT 'POST',
  path TEXT NOT NULL,
  status_code INTEGER NOT NULL,
  response_body JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_idempotency_created_at
  ON api_idempotency (created_at DESC);
