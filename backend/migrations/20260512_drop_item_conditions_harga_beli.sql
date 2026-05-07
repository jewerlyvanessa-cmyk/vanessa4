-- Drop deprecated buyback field from item_conditions.
-- Safe for repeated runs.

BEGIN;

ALTER TABLE IF EXISTS item_conditions
  DROP COLUMN IF EXISTS harga_beli;

COMMIT;
