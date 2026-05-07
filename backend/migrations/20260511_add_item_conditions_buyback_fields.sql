-- Ensure buyback-specific columns exist on item_conditions
-- Safe to run multiple times.

BEGIN;

ALTER TABLE IF EXISTS item_conditions
  ADD COLUMN IF NOT EXISTS harga_per_gram NUMERIC(15,2);

ALTER TABLE IF EXISTS item_conditions
  ADD COLUMN IF NOT EXISTS potongan_kondisi NUMERIC(15,2) DEFAULT 0;

ALTER TABLE IF EXISTS item_conditions
  ADD COLUMN IF NOT EXISTS untung_rugi VARCHAR(20);

-- Optional but useful to persist explicit profit/loss amount from buyback form
ALTER TABLE IF EXISTS item_conditions
  ADD COLUMN IF NOT EXISTS nilai_untung_rugi NUMERIC(15,2) DEFAULT 0;

COMMIT;
