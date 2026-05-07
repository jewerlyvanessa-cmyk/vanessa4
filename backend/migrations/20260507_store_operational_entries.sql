-- Catatan pengeluaran / operasional toko (kasir & modul terkait)
-- Date: 2026-05-07

CREATE TABLE IF NOT EXISTS store_operational_entries (
  entry_id BIGSERIAL PRIMARY KEY,
  branch_id BIGINT NOT NULL,
  user_id BIGINT,
  amount NUMERIC(15, 2) NOT NULL CHECK (amount > 0),
  category TEXT NOT NULL,
  notes TEXT,
  entry_kind TEXT NOT NULL DEFAULT 'expense'
    CHECK (entry_kind IN ('expense', 'income')),
  proof_photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_ops_branch_created
  ON store_operational_entries (branch_id, created_at DESC);
