-- Migration script to apply the new database design from perubahan.txt
-- Run this script to update the existing database to the new schema

-- Step 1: Backup existing data (recommended)
-- You should backup your data before running this migration

-- Step 2: Add new columns to items table
ALTER TABLE items ADD COLUMN IF NOT EXISTS item_code TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS item_code_source TEXT DEFAULT 'internal';
ALTER TABLE items ADD COLUMN IF NOT EXISTS qr_code TEXT UNIQUE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;
ALTER TABLE items ADD COLUMN IF NOT EXISTS kategori TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS jenis TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS tipe TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS ownership TEXT CHECK (ownership IN ('toko','pelanggan','unknown')) DEFAULT 'unknown';
ALTER TABLE items ADD COLUMN IF NOT EXISTS stock_type TEXT CHECK (stock_type IN ('inventory','non_inventory')) DEFAULT 'non_inventory';
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_quick_registered BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_estimated BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual';

-- Step 3: Make weight nullable (as per new design)
ALTER TABLE items ALTER COLUMN weight DROP NOT NULL;
ALTER TABLE items ALTER COLUMN material DROP NOT NULL;
ALTER TABLE items ALTER COLUMN purity DROP NOT NULL;

-- Step 4: Update existing items to have proper ownership and stock_type
UPDATE items SET ownership = 'toko' WHERE ownership IS NULL;
UPDATE items SET stock_type = 'inventory' WHERE stock_type IS NULL AND status = 'ready';
UPDATE items SET stock_type = 'non_inventory' WHERE stock_type IS NULL;

-- Step 5: Add customers table if not exists
CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Step 6: Add new columns to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id BIGINT REFERENCES customers(customer_id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS nota_order TEXT UNIQUE;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (
    status IN ('draft','submitted','in_progress','done','cancelled')
);
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_type_check;
ALTER TABLE orders ADD CONSTRAINT orders_order_type_check CHECK (
    order_type IN ('jual','buyback','service','custom')
);

-- Step 7: Update stock_history table
ALTER TABLE stock_history ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE stock_history DROP COLUMN IF EXISTS timestamp;
ALTER TABLE stock_history ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT now();

-- Step 8: Create sequence and functions
CREATE SEQUENCE IF NOT EXISTS order_nota_seq
START 1
INCREMENT 1
MINVALUE 1
NO CYCLE;

-- Update branches table to have initials column if not exists
ALTER TABLE branches ADD COLUMN IF NOT EXISTS initials TEXT;

-- Function to generate nota order
CREATE OR REPLACE FUNCTION generate_nota_order(
  p_branch_id BIGINT,
  p_order_type TEXT
)
RETURNS TEXT AS $$
DECLARE
  v_initial TEXT;
  v_code TEXT;
  v_order_code TEXT;
  v_seq BIGINT;
BEGIN
  SELECT COALESCE(initials, LEFT(name, 2)), code
  INTO v_initial, v_code
  FROM branches
  WHERE branch_id = p_branch_id;

  v_order_code := CASE p_order_type
    WHEN 'jual' THEN 'JL'
    WHEN 'buyback' THEN 'BB'
    WHEN 'service' THEN 'SV'
    WHEN 'custom' THEN 'CT'
    ELSE NULL
  END;

  IF v_order_code IS NULL THEN
    RAISE EXCEPTION 'Invalid order_type: %', p_order_type;
  END IF;

  v_seq := nextval('order_nota_seq');

  RETURN UPPER(v_initial) || '-' || UPPER(v_code) || '-' || v_order_code || '-' || LPAD(v_seq::TEXT, 8, '0');
END;
$$ LANGUAGE plpgsql;

-- Trigger to prevent nota_order updates
CREATE OR REPLACE FUNCTION prevent_nota_order_update()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.nota_order IS NOT NULL AND NEW.nota_order <> OLD.nota_order THEN
    RAISE EXCEPTION 'nota_order cannot be modified';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_nota_update ON orders;
CREATE TRIGGER trg_prevent_nota_update
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION prevent_nota_order_update();

-- Step 9: Create unique index for item_code per branch
CREATE UNIQUE INDEX IF NOT EXISTS uq_item_code_branch
ON items(branch_id, item_code)
WHERE item_code IS NOT NULL;

-- Step 10: Update existing data
-- Set default values for new fields
UPDATE items SET
  ownership = 'toko',
  stock_type = CASE WHEN status = 'ready' THEN 'inventory' ELSE 'non_inventory' END,
  source = 'manual',
  is_quick_registered = false,
  is_estimated = false
WHERE ownership IS NULL OR stock_type IS NULL;

-- Generate item_codes for existing items (optional - you may want to do this manually)
-- UPDATE items SET item_code = 'AUTO-' || item_id::TEXT WHERE item_code IS NULL;

COMMIT;
