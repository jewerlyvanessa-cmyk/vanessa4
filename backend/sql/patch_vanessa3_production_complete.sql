-- =============================================================================
-- Patch production / legacy DB → selaras dengan backend + vanessa3_schema
-- Aman dijalankan berulang (IF NOT EXISTS / DROP IF EXISTS constraint).
--
-- Cara pakai (tab/query BARU; jika error transaksi: jalankan ROLLBACK; dulu):
--   psql -U postgres -d vanessa_store -f backend/sql/patch_vanessa3_production_complete.sql
--
-- Jangan gabung dengan query lain dalam satu transaksi gagal di GUI SQL.
-- =============================================================================

-- --- Nota order (POST /orders) ---
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

-- --- branches ---
ALTER TABLE branches ADD COLUMN IF NOT EXISTS alias TEXT;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS initials TEXT;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
ALTER TABLE branches ADD COLUMN IF NOT EXISTS branch_type TEXT DEFAULT 'toko';
ALTER TABLE branches ADD COLUMN IF NOT EXISTS logo_url TEXT;

UPDATE branches SET branch_type = 'toko' WHERE branch_type IS NULL;
UPDATE branches SET status = 'active' WHERE status IS NULL;
UPDATE branches SET initials = UPPER(LEFT(code, 3))
  WHERE initials IS NULL OR TRIM(initials) = '';

DO $$ BEGIN
  ALTER TABLE branches ADD CONSTRAINT branches_branch_type_check
    CHECK (branch_type IN ('toko', 'warehouse', 'workshop', 'pusat'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE branches ADD CONSTRAINT branches_status_check
    CHECK (status IN ('active', 'inactive'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- --- customers ---
ALTER TABLE customers ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE customers ADD COLUMN IF NOT EXISTS metadata JSONB;

-- --- items (penjualan, buyback, transfer) ---
ALTER TABLE items ADD COLUMN IF NOT EXISTS photo_produk TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users (user_id);
ALTER TABLE items ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;
UPDATE items SET quantity = 1 WHERE quantity IS NULL;
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

ALTER TABLE items DROP CONSTRAINT IF EXISTS items_kode_produk_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'items_branch_id_kode_produk_key'
  ) THEN
    ALTER TABLE items
      ADD CONSTRAINT items_branch_id_kode_produk_key UNIQUE (branch_id, kode_produk);
  END IF;
END $$;

-- --- orders (pembayaran kasir, workshop, pickup) ---
ALTER TABLE orders ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::JSONB;
UPDATE orders SET metadata = '{}'::JSONB WHERE metadata IS NULL;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_amount NUMERIC(14, 2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_due_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_duration_text TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_notes TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_by BIGINT REFERENCES users (user_id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_notes TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_photo_url TEXT;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (
  status IN (
    'draft', 'pending', 'confirmed', 'ready_for_payment', 'completed',
    'picked_up', 'cancelled', 'buyback', 'delivered', 'sold',
    'awaiting_warehouse', 'sent-to-workshop', 'in_workshop', 'repairing',
    'polishing', 'custom_work', 'done_workshop', 'ready_for_pickup'
  )
);

-- --- payments ---
ALTER TABLE payments ADD COLUMN IF NOT EXISTS proof_url TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS revenue_branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS validated_by BIGINT REFERENCES users (user_id);

-- --- transfers ---
ALTER TABLE transfers ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'stok';
ALTER TABLE transfers ADD COLUMN IF NOT EXISTS courier TEXT;

-- --- user_branch_roles ---
ALTER TABLE user_branch_roles ADD COLUMN IF NOT EXISTS is_primary BOOLEAN DEFAULT FALSE;
UPDATE user_branch_roles SET is_primary = FALSE WHERE is_primary IS NULL;

ALTER TABLE user_branch_roles DROP CONSTRAINT IF EXISTS user_branch_roles_role_check;
ALTER TABLE user_branch_roles ADD CONSTRAINT user_branch_roles_role_check CHECK (
  role IN (
    'cs', 'kasir', 'admin_toko', 'admin_workshop', 'admin_warehouse',
    'tukang', 'manajer', 'superadmin', 'stockist'
  )
);
