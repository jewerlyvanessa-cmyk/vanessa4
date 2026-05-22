-- Patch untuk database yang sudah ada (skema lama) sebelum seed_minimal.sql
-- Aman dijalankan berulang (IF NOT EXISTS).
--
-- PENTING — jika muncul "current transaction is aborted":
--   1. Buka tab/query BARU (jangan pakai tab yang error)
--   2. Jalankan HANYA:  ROLLBACK;
--   3. Tab BARU lagi → jalankan patch_items_ownership_only.sql (lebih aman)
--      atau file ini dari awal
--
-- Jangan centang "Execute in transaction" / "Auto-commit off" di client SQL.
-- Dari terminal (disarankan): psql ... -f patch_items_ownership_only.sql

-- branches
ALTER TABLE branches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
ALTER TABLE branches ADD COLUMN IF NOT EXISTS branch_type TEXT DEFAULT 'toko';
ALTER TABLE branches ADD COLUMN IF NOT EXISTS logo_url TEXT;

UPDATE branches SET branch_type = 'toko' WHERE branch_type IS NULL;
UPDATE branches SET status = 'active' WHERE status IS NULL;

ALTER TABLE branches ALTER COLUMN branch_type SET DEFAULT 'toko';
ALTER TABLE branches ALTER COLUMN branch_type SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE branches
    ADD CONSTRAINT branches_branch_type_check
    CHECK (branch_type IN ('toko', 'warehouse', 'workshop', 'pusat'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE branches
    ADD CONSTRAINT branches_status_check
    CHECK (status IN ('active', 'inactive'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- customers
ALTER TABLE customers ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE customers ADD COLUMN IF NOT EXISTS metadata JSONB;

-- items
ALTER TABLE items ADD COLUMN IF NOT EXISTS photo_produk TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users (user_id);
ALTER TABLE items ADD COLUMN IF NOT EXISTS quantity INTEGER NOT NULL DEFAULT 1;
ALTER TABLE items ADD COLUMN IF NOT EXISTS ownership TEXT DEFAULT 'unknown';
ALTER TABLE items ADD COLUMN IF NOT EXISTS stock_type TEXT DEFAULT 'non_inventory';
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_quick_registered BOOLEAN DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_estimated BOOLEAN DEFAULT FALSE;

UPDATE items SET ownership = 'unknown' WHERE ownership IS NULL;
UPDATE items SET stock_type = 'non_inventory' WHERE stock_type IS NULL;
UPDATE items SET is_quick_registered = FALSE WHERE is_quick_registered IS NULL;
UPDATE items SET is_estimated = FALSE WHERE is_estimated IS NULL;

DO $$
BEGIN
  ALTER TABLE items
    ADD CONSTRAINT items_ownership_check
    CHECK (ownership IN ('toko', 'pelanggan', 'unknown'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE items
    ADD CONSTRAINT items_stock_type_check
    CHECK (stock_type IN ('inventory', 'non_inventory'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_items_ownership ON items (ownership);

-- orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_amount NUMERIC(14, 2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_due_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_duration_text TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimate_notes TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_by BIGINT REFERENCES users (user_id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_notes TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_up_photo_url TEXT;

-- payments
ALTER TABLE payments ADD COLUMN IF NOT EXISTS proof_url TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS revenue_branch_id BIGINT REFERENCES branches (branch_id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS validated_by BIGINT REFERENCES users (user_id);

-- transfers
ALTER TABLE transfers ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'stok';
ALTER TABLE transfers ADD COLUMN IF NOT EXISTS courier TEXT;

-- user_branch_roles: perluas role check
ALTER TABLE user_branch_roles DROP CONSTRAINT IF EXISTS user_branch_roles_role_check;
ALTER TABLE user_branch_roles ADD CONSTRAINT user_branch_roles_role_check CHECK (
  role IN (
    'cs', 'kasir', 'admin_toko', 'admin_workshop', 'admin_warehouse',
    'tukang', 'manajer', 'superadmin', 'stockist', 'owner'
  )
);
