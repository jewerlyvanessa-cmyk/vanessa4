-- Drop kerusakan column from item_conditions table.
-- Safe for repeated runs.

BEGIN;

ALTER TABLE IF EXISTS item_conditions
  DROP COLUMN IF EXISTS kerusakan;

COMMIT;
