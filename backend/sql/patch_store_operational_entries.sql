-- Keuangan toko (kasir): tabel store_operational_entries
-- Jalankan sekali di production jika GET /store-operational mengembalikan 503/500 (tabel/kolom belum ada).

CREATE TABLE IF NOT EXISTS store_operational_entries (
  entry_id BIGSERIAL PRIMARY KEY,
  branch_id BIGINT NOT NULL,
  user_id BIGINT,
  amount NUMERIC(15, 2) NOT NULL CHECK (amount > 0),
  category TEXT NOT NULL,
  notes TEXT,
  entry_kind TEXT NOT NULL DEFAULT 'expense',
  proof_photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE store_operational_entries
  ADD COLUMN IF NOT EXISTS entry_kind TEXT NOT NULL DEFAULT 'expense';

ALTER TABLE store_operational_entries
  ADD COLUMN IF NOT EXISTS proof_photo_url TEXT;

UPDATE store_operational_entries
SET entry_kind = 'expense'
WHERE entry_kind IS NULL;

DO $$
BEGIN
  ALTER TABLE store_operational_entries
    ADD CONSTRAINT store_operational_entries_entry_kind_check
    CHECK (entry_kind IN ('expense', 'income'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_store_ops_branch_created
  ON store_operational_entries (branch_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_store_ops_branch_user_created
  ON store_operational_entries (branch_id, user_id, created_at DESC);
