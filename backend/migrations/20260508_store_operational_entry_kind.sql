-- Pemasukan vs pengeluaran pada catatan keuangan toko
-- Date: 2026-05-08

ALTER TABLE store_operational_entries
  ADD COLUMN IF NOT EXISTS entry_kind TEXT NOT NULL DEFAULT 'expense';

UPDATE store_operational_entries
SET entry_kind = 'expense'
WHERE entry_kind IS NULL OR entry_kind NOT IN ('expense', 'income');

ALTER TABLE store_operational_entries
  DROP CONSTRAINT IF EXISTS store_operational_entries_entry_kind_check;

ALTER TABLE store_operational_entries
  ADD CONSTRAINT store_operational_entries_entry_kind_check
  CHECK (entry_kind IN ('expense', 'income'));
