-- Migration: Add source_type column to transfers
-- Date: 2026-04-26
-- Description: Track source of transferred goods (stok / buyback)

BEGIN;

ALTER TABLE transfers
  ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'stok'
  CHECK (source_type IN ('stok', 'buyback'));

COMMIT;

