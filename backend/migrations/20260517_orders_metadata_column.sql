-- Kolom metadata untuk service/custom (cabang workshop, penugasan tukang, dll.)

BEGIN;

ALTER TABLE IF EXISTS orders
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMIT;
