-- Migration: Move items.photo_url -> items.photo_produk, then drop photo_url
-- Date: 2026-04-30
-- Rationale: Standardize item photo field naming; keep order_items.photo_produk as-is.

BEGIN;

ALTER TABLE items
  ADD COLUMN IF NOT EXISTS photo_produk TEXT;

-- Backfill from old column if it still exists.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'items'
      AND column_name = 'photo_url'
  ) THEN
    UPDATE items
    SET photo_produk = COALESCE(photo_produk, photo_url)
    WHERE photo_produk IS NULL OR trim(photo_produk) = '';
  END IF;
END $$;

ALTER TABLE items
  DROP COLUMN IF EXISTS photo_url;

COMMIT;

