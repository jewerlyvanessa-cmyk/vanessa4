-- Patch untuk database yang sudah ada (skema lama) sebelum seed_minimal.sql
-- Aman dijalankan berulang (IF NOT EXISTS).
--
-- PENTING — jika muncul "current transaction is aborted":
--   Jalankan SATU baris ini dulu di tab query baru, lalu Execute:
--   ROLLBACK;
--
-- (Tanpa BEGIN/COMMIT agar tiap perintah commit sendiri di Database Client)

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
    'tukang', 'manajer', 'superadmin', 'stockist'
  )
);
