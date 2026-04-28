-- Migration: Fix unique constraint for items.kode_produk
-- Date: 2026-04-26
-- Description:
--   Some DBs were created with a global unique constraint on items(kode_produk),
--   which prevents using the same kode_produk across branches.
--   The intended constraint is per-branch uniqueness: UNIQUE(branch_id, kode_produk).

BEGIN;

-- Drop legacy global unique constraint if it exists
ALTER TABLE items
  DROP CONSTRAINT IF EXISTS items_kode_produk_key;

-- Ensure the intended composite unique constraint exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'items_branch_id_kode_produk_key'
  ) THEN
    ALTER TABLE items
      ADD CONSTRAINT items_branch_id_kode_produk_key UNIQUE (branch_id, kode_produk);
  END IF;
END $$;

COMMIT;

