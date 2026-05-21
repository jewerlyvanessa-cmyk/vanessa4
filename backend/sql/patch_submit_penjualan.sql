-- DEPRECATED: gunakan patch_vanessa3_production_complete.sql (lebih lengkap).
-- File ini hanya subset nota + items.
-- psql -U postgres -d vanessa_store -f backend/sql/patch_vanessa3_production_complete.sql

-- 1) Nomor nota
CREATE SEQUENCE IF NOT EXISTS order_nota_seq START 1 INCREMENT 1 MINVALUE 1 NO CYCLE;

CREATE OR REPLACE FUNCTION generate_nota_order(
  p_branch_id BIGINT,
  p_order_type TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_initial TEXT;
  v_code TEXT;
  v_order_code TEXT;
  v_seq BIGINT;
BEGIN
  SELECT initials, code INTO v_initial, v_code FROM branches WHERE branch_id = p_branch_id;
  v_order_code := CASE p_order_type
    WHEN 'jual' THEN 'JL' WHEN 'buyback' THEN 'BB'
    WHEN 'service' THEN 'SV' WHEN 'custom' THEN 'CT' ELSE NULL END;
  IF v_order_code IS NULL THEN
    RAISE EXCEPTION 'Invalid order_type: %', p_order_type;
  END IF;
  v_seq := nextval('order_nota_seq');
  RETURN COALESCE(NULLIF(TRIM(v_initial), ''), 'XX') || '-'
    || COALESCE(NULLIF(TRIM(v_code), ''), 'BR') || '-'
    || v_order_code || '-' || LPAD(v_seq::TEXT, 8, '0');
END;
$$;

ALTER TABLE branches ADD COLUMN IF NOT EXISTS initials TEXT;
UPDATE branches SET initials = UPPER(LEFT(code, 3)) WHERE initials IS NULL OR TRIM(initials) = '';

-- 2) Kolom items
ALTER TABLE items ADD COLUMN IF NOT EXISTS ownership TEXT DEFAULT 'unknown';
ALTER TABLE items ADD COLUMN IF NOT EXISTS stock_type TEXT DEFAULT 'non_inventory';
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_quick_registered BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_estimated BOOLEAN DEFAULT FALSE;

UPDATE items SET ownership = 'unknown' WHERE ownership IS NULL;
UPDATE items SET stock_type = 'non_inventory' WHERE stock_type IS NULL;
UPDATE items SET is_quick_registered = FALSE WHERE is_quick_registered IS NULL;
UPDATE items SET is_estimated = FALSE WHERE is_estimated IS NULL;

DO $$ BEGIN
  ALTER TABLE items ADD CONSTRAINT items_ownership_check
    CHECK (ownership IN ('toko', 'pelanggan', 'unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE items ADD CONSTRAINT items_stock_type_check
    CHECK (stock_type IN ('inventory', 'non_inventory'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_items_ownership ON items (ownership);
