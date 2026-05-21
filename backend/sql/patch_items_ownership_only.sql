-- Patch MINIMAL: kolom items untuk submit penjualan (ownership, stock_type, …)
-- Jalankan SETELAH ROLLBACK jika muncul "current transaction is aborted".
--
-- Langkah di Database Client (DBeaver, pgAdmin, dll.):
--   1. Tab/query BARU → jalankan hanya:  ROLLBACK;
--   2. Tab/query BARU → jalankan file ini (jangan gabung dengan query lain)
--
-- Atau dari terminal:
--   psql -U postgres -d vanessa_store -f backend/sql/patch_items_ownership_only.sql

ALTER TABLE items ADD COLUMN IF NOT EXISTS ownership TEXT DEFAULT 'unknown';
ALTER TABLE items ADD COLUMN IF NOT EXISTS stock_type TEXT DEFAULT 'non_inventory';
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_quick_registered BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_estimated BOOLEAN DEFAULT FALSE;

UPDATE items SET ownership = 'unknown' WHERE ownership IS NULL;
UPDATE items SET stock_type = 'non_inventory' WHERE stock_type IS NULL;
UPDATE items SET is_quick_registered = FALSE WHERE is_quick_registered IS NULL;
UPDATE items SET is_estimated = FALSE WHERE is_estimated IS NULL;

DO $$
BEGIN
  ALTER TABLE items
    ADD CONSTRAINT items_ownership_check
    CHECK (ownership IN ('toko', 'pelanggan', 'unknown'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE items
    ADD CONSTRAINT items_stock_type_check
    CHECK (stock_type IN ('inventory', 'non_inventory'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_items_ownership ON items (ownership);
